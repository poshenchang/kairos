// lib/data/repositories/task_repository.dart
//
// Repository that wraps TaskDao and adds recurring-task business logic.
//
// No direct Drift imports — all DB access is delegated to TaskDao.
//
// Real schema note:
//   - The deadline column is named `dueDate` in the Tasks table.
//   - The RRULE is stored in the `rrule` column.
//   - Recurring tasks are flagged with `isRecurring = true`.

import 'package:drift/drift.dart' show Value;

import 'package:kairos/data/database/app_database.dart';

/// Wraps [TaskDao] and adds higher-level task operations, including
/// recurring-task next-occurrence computation and dashboard aggregation.
class TaskRepository {
  const TaskRepository(this._dao);

  final TaskDao _dao;

  // ── Recurring task logic ─────────────────────────────────────────────────

  /// Given a recurring [task], computes the next occurrence after [now] (or
  /// `DateTime.now()` when not provided) and returns a transient [Task] whose
  /// [dueDate] is set to that occurrence.
  ///
  /// Returns `null` when:
  ///   - [task.isRecurring] is `false` or [task.rrule] is `null` / empty.
  ///   - The RRULE frequency is unsupported (only `FREQ=WEEKLY` is handled).
  ///   - No occurrence is found within the next 365 days.
  ///
  /// The returned [Task] is **not persisted** — it is a transient copy of the
  /// base task with the adjusted [dueDate].
  Task? getNextInstanceOfRecurringTask(Task task, {DateTime? now}) {
    if (!task.isRecurring) return null;
    final rule = task.rrule;
    if (rule == null || rule.isEmpty) return null;

    final params = _parseRule(rule);
    final freq = params['FREQ'];
    if (freq != 'WEEKLY' && freq != 'DAILY') return null;

    final untilDate = params['UNTIL'] != null ? _parseUntil(params['UNTIL']!) : null;
    final maxCount = params['COUNT'] != null ? int.tryParse(params['COUNT']!) : null;
    if (maxCount != null && maxCount <= 0) return null;

    final reference = (now ?? DateTime.now());
    final baseDue = task.dueDate;

    if (freq == 'DAILY') {
      final candidate = reference.add(const Duration(days: 1));
      final nextDueDate = DateTime(
        candidate.year,
        candidate.month,
        candidate.day,
        baseDue.hour,
        baseDue.minute,
        baseDue.second,
      );
      if (untilDate != null && nextDueDate.isAfter(untilDate)) return null;
      return task.copyWith(
        dueDate: nextDueDate,
        isCompleted: false,
        completedAt: const Value(null),
      );
    }

    final byDay = params['BYDAY'];
    final targetWeekdays = byDay != null ? _parseByday(byDay) : <int>{};
    if (targetWeekdays.isEmpty) {
      targetWeekdays.add(baseDue.weekday);
    }

    // Walk forward day-by-day from tomorrow to find the next matching weekday.
    for (var i = 1; i <= 365; i++) {
      final candidate = reference.add(Duration(days: i));
      if (targetWeekdays.contains(candidate.weekday)) {
        final nextDueDate = DateTime(
          candidate.year,
          candidate.month,
          candidate.day,
          baseDue.hour,
          baseDue.minute,
          baseDue.second,
        );

        if (untilDate != null && nextDueDate.isAfter(untilDate)) {
          return null; // Past UNTIL date
        }

        return task.copyWith(
          dueDate: nextDueDate,
          isCompleted: false,
          completedAt: const Value(null),
        );
      }
    }

    return null;
  }

  /// Returns tasks for the dashboard sorted by [dueDate] ascending.
  /// Incomplete tasks already reflect the current active occurrence for both
  /// one-off tasks and recurring tasks.
  Future<List<Task>> getDashboardTasks({DateTime? now}) async {
    final incompleteTasks = await _dao.getIncompleteTasks();
    final result = List<Task>.from(incompleteTasks);
    result.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return result;
  }


  /// Completes a task:
  /// - For one-off tasks: marks completed in database.
  /// - For recurring tasks: advances [dueDate] to the next occurrence, resets
  ///   subtasks to incomplete, and decrements COUNT if present.
  ///   If the recurrence has finished (past UNTIL date or COUNT reached 1),
  ///   marks the task completed permanently.
  Future<bool> completeTask(int id) async {
    final task = await _dao.getTaskById(id);
    if (task == null) return false;

    if (task.isRecurring && task.rrule != null && task.rrule!.isNotEmpty) {
      final reference = task.dueDate.isAfter(DateTime.now())
          ? task.dueDate
          : DateTime.now();
      final next = getNextInstanceOfRecurringTask(task, now: reference);
      if (next != null) {
        final params = _parseRule(task.rrule!);
        String? newRrule = task.rrule;
        if (params.containsKey('COUNT')) {
          final count = int.tryParse(params['COUNT'] ?? '');
          if (count != null) {
            if (count <= 1) {
              // Last occurrence completed! Mark completed for good
              final rows = await _dao.markCompleted(id);
              return rows > 0;
            } else {
              newRrule = task.rrule!.replaceAll('COUNT=$count', 'COUNT=${count - 1}');
            }
          }
        }

        // Advance to next occurrence
        await _dao.updateTask(task.toCompanion(true).copyWith(
          dueDate: Value(next.dueDate),
          isCompleted: const Value(false),
          completedAt: const Value(null),
          rrule: Value(newRrule),
          updatedAt: Value(DateTime.now().toUtc()),
        ));

        // Reset subtasks for the new occurrence
        await _dao.resetSubtasksForTask(id);
        return true;
      }
    }

    final rows = await _dao.markCompleted(id);
    return rows > 0;
  }

  // ── TaskDao delegation ────────────────────────────────────────────────────

  Stream<List<Task>> watchIncompleteTasks() => _dao.watchIncompleteTasks();

  Stream<List<Task>> watchTasksDueSoon(DateTime threshold) =>
      _dao.watchTasksDueSoon(threshold);

  Stream<List<Task>> watchTasksForCategory(String category) =>
      _dao.watchTasksForCategory(category);

  Future<List<Task>> getIncompleteTasks() => _dao.getIncompleteTasks();

  Future<int> insertTask(TasksCompanion task) => _dao.insertTask(task);

  Future<bool> updateTask(TasksCompanion task) => _dao.updateTask(task);

  Future<int> deleteTask(int id) => _dao.deleteTask(id);

  // ── Private helpers ───────────────────────────────────────────────────────

  DateTime? _parseUntil(String untilStr) {
    try {
      final clean = untilStr.replaceAll('-', '').replaceAll(':', '');
      if (clean.length >= 8) {
        final y = int.parse(clean.substring(0, 4));
        final m = int.parse(clean.substring(4, 6));
        final d = int.parse(clean.substring(6, 8));
        return DateTime(y, m, d, 23, 59, 59);
      }
    } catch (_) {}
    return null;
  }

  /// Parses `FREQ=WEEKLY;BYDAY=MO,FR` into `{'FREQ':'WEEKLY','BYDAY':'MO,FR'}`.
  Map<String, String> _parseRule(String rule) => {
        for (final part in rule.split(';'))
          if (part.contains('='))
            part.split('=').first.trim().toUpperCase():
                part.split('=').last.trim().toUpperCase(),
      };

  /// Maps BYDAY token strings to [DateTime.weekday] integers.
  /// e.g. 'TU,TH' → {2, 4}
  Set<int> _parseByday(String byday) {
    const dayMap = {
      'MO': DateTime.monday,
      'TU': DateTime.tuesday,
      'WE': DateTime.wednesday,
      'TH': DateTime.thursday,
      'FR': DateTime.friday,
      'SA': DateTime.saturday,
      'SU': DateTime.sunday,
    };
    return {
      for (final token in byday.split(','))
        if (dayMap.containsKey(token.trim())) dayMap[token.trim()]!,
    };
  }
}
