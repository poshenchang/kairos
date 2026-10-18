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
import 'package:kairos/data/database/daos/task_dao.dart';

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
    if (params['FREQ'] != 'WEEKLY') return null;

    final byDay = params['BYDAY'];
    if (byDay == null || byDay.isEmpty) return null;

    final targetWeekdays = _parseByday(byDay);
    if (targetWeekdays.isEmpty) return null;

    final reference = (now ?? DateTime.now());
    final baseDue = task.dueDate;

    // Walk forward day-by-day from tomorrow to find the next matching weekday.
    // Limit the search to 365 days to avoid an infinite loop.
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

        // Return a transient copy — NOT persisted to the DB.
        return task.copyWith(
          dueDate: nextDueDate,
          isCompleted: false,
          completedAt: const Value(null),
        );
      }
    }

    return null; // No occurrence found within 1 year.
  }

  /// Returns tasks for the dashboard:
  ///   - One-off incomplete tasks are returned as-is.
  ///   - Recurring tasks are collapsed to show only the **next** occurrence
  ///     after [now] (one entry per recurring task).
  ///   - Result is sorted by [dueDate] ascending.
  Future<List<Task>> getDashboardTasks({DateTime? now}) async {
    final incompleteTasks = await _dao.getIncompleteTasks();
    final reference = now ?? DateTime.now();

    final result = <Task>[];
    for (final task in incompleteTasks) {
      if (task.isRecurring) {
        final next = getNextInstanceOfRecurringTask(task, now: reference);
        if (next != null) result.add(next);
      } else {
        result.add(task);
      }
    }

    result.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return result;
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

  Future<bool> completeTask(int id) => _dao.completeTask(id);

  // ── Private helpers ───────────────────────────────────────────────────────

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
