// lib/data/database/daos/habit_dao.dart
//
// Data-access object for Habits and HabitLogs.

import 'package:drift/drift.dart';
import 'package:kairos/data/database/app_database.dart';

part 'habit_dao.g.dart';

@DriftAccessor(tables: [Habits, HabitLogs])
class HabitDao extends DatabaseAccessor<AppDatabase> with _$HabitDaoMixin {
  HabitDao(super.db);

  // ── Habit Queries ─────────────────────────────────────────────────────────

  Future<List<Habit>> getAllActiveHabits() =>
      (select(habits)
            ..where((h) => h.isDeleted.equals(false) & h.isActive.equals(true)))
          .get();

  Future<Habit?> getHabitById(int id) =>
      (select(habits)..where((h) => h.id.equals(id))).getSingleOrNull();

  Stream<List<Habit>> watchActiveHabits() =>
      (select(habits)
            ..where((h) => h.isDeleted.equals(false) & h.isActive.equals(true)))
          .watch();

  // ── HabitLog Queries ──────────────────────────────────────────────────────

  /// Returns a map of habitId → session count completed within [weekStart, weekEnd].
  /// For daily habits (targetFrequencyPerWeek >= 7), multiple entries in a single calendar
  /// day only count as 1 completion.
  Future<Map<int, int>> getWeeklyCompletions(
      DateTime weekStart, DateTime weekEnd) async {
    final logs = await (select(habitLogs)
          ..where(
            (l) =>
                l.isDeleted.equals(false) &
                l.completedAt.isBiggerOrEqualValue(weekStart) &
                l.completedAt.isSmallerThanValue(weekEnd),
          ))
        .get();

    final allHabits = await getAllActiveHabits();
    final dailyHabitIds = {
      for (final h in allHabits)
        if (h.targetFrequencyPerWeek >= 7) h.id
    };

    final result = <int, int>{};
    final dailyHabitDays = <int, Set<String>>{};

    for (final log in logs) {
      if (dailyHabitIds.contains(log.habitId)) {
        final localDate = log.completedAt.toLocal();
        final dayKey = '${localDate.year}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}';
        final days = dailyHabitDays.putIfAbsent(log.habitId, () => <String>{});
        days.add(dayKey);
        result[log.habitId] = days.length;
      } else {
        result[log.habitId] = (result[log.habitId] ?? 0) + 1;
      }
    }
    return result;
  }

  /// Real-time reactive stream of habitId → session count completed within [weekStart, weekEnd].
  /// For daily habits (targetFrequencyPerWeek >= 7), multiple entries in a single calendar
  /// day only count as 1 completion.
  Stream<Map<int, int>> watchWeeklyCompletions(
      DateTime weekStart, DateTime weekEnd) {
    return (select(habitLogs)
          ..where(
            (l) =>
                l.isDeleted.equals(false) &
                l.completedAt.isBiggerOrEqualValue(weekStart) &
                l.completedAt.isSmallerThanValue(weekEnd),
          ))
        .watch()
        .asyncMap((logs) async {
      final allHabits = await getAllActiveHabits();
      final dailyHabitIds = {
        for (final h in allHabits)
          if (h.targetFrequencyPerWeek >= 7) h.id
      };

      final result = <int, int>{};
      final dailyHabitDays = <int, Set<String>>{};

      for (final log in logs) {
        if (dailyHabitIds.contains(log.habitId)) {
          final localDate = log.completedAt.toLocal();
          final dayKey = '${localDate.year}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}';
          final days = dailyHabitDays.putIfAbsent(log.habitId, () => <String>{});
          days.add(dayKey);
          result[log.habitId] = days.length;
        } else {
          result[log.habitId] = (result[log.habitId] ?? 0) + 1;
        }
      }
      return result;
    });
  }

  Future<List<HabitLog>> getLogsForHabit(int habitId,
      {DateTime? from, DateTime? to}) {
    final query = select(habitLogs)
      ..where((l) => l.habitId.equals(habitId) & l.isDeleted.equals(false));
    if (from != null) {
      query.where((l) => l.completedAt.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where((l) => l.completedAt.isSmallerThanValue(to));
    }
    return query.get();
  }

  Stream<List<HabitLog>> watchAllHabitLogs() =>
      (select(habitLogs)..where((l) => l.isDeleted.equals(false))).watch();

  /// For daily habits (targetFrequencyPerWeek >= 7), finds duplicate entries
  /// logged on the same calendar day (local date) and marks the extras as isDeleted = true.
  /// Returns the number of duplicate logs marked as deleted.
  Future<int> deduplicateDailyHabitLogs() async {
    final activeHabits = await getAllActiveHabits();
    final dailyHabits = activeHabits.where((h) => h.targetFrequencyPerWeek >= 7).toList();
    if (dailyHabits.isEmpty) return 0;

    int totalDeduplicated = 0;
    final nowUtc = DateTime.now().toUtc();

    for (final habit in dailyHabits) {
      final logs = await (select(habitLogs)
            ..where((l) => l.habitId.equals(habit.id) & l.isDeleted.equals(false))
            ..orderBy([(l) => OrderingTerm(expression: l.completedAt)]))
          .get();

      final seenDays = <String>{};
      for (final log in logs) {
        final localDate = log.completedAt.toLocal();
        final dayKey = '${localDate.year}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}';
        if (seenDays.contains(dayKey)) {
          await (update(habitLogs)..where((l) => l.id.equals(log.id))).write(
            HabitLogsCompanion(
              isDeleted: const Value(true),
              updatedAt: Value(nowUtc),
            ),
          );
          totalDeduplicated++;
        } else {
          seenDays.add(dayKey);
        }
      }
    }
    return totalDeduplicated;
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  Future<int> insertHabit(HabitsCompanion companion) =>
      into(habits).insert(companion);

  Future<bool> updateHabit(HabitsCompanion companion) =>
      update(habits).replace(companion);

  Future<int> deleteHabit(int id) => (update(habits)
        ..where((h) => h.id.equals(id)))
      .write(HabitsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now().toUtc()),
      ));

  Future<int> logHabitCompletion(HabitLogsCompanion companion) =>
      into(habitLogs).insert(companion);

  Future<int> deleteHabitLog(int id) => (update(habitLogs)
        ..where((l) => l.id.equals(id)))
      .write(HabitLogsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now().toUtc()),
      ));
}
