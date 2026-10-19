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
  Future<Map<int, int>> getWeeklyCompletions(
      DateTime weekStart, DateTime weekEnd) async {
    final logs = await (select(habitLogs)
          ..where(
            (l) =>
                l.completedAt.isBiggerOrEqualValue(weekStart) &
                l.completedAt.isSmallerThanValue(weekEnd),
          ))
        .get();

    final result = <int, int>{};
    for (final log in logs) {
      result[log.habitId] = (result[log.habitId] ?? 0) + 1;
    }
    return result;
  }

  /// Real-time reactive stream of habitId → session count completed within [weekStart, weekEnd].
  Stream<Map<int, int>> watchWeeklyCompletions(
      DateTime weekStart, DateTime weekEnd) {
    return (select(habitLogs)
          ..where(
            (l) =>
                l.completedAt.isBiggerOrEqualValue(weekStart) &
                l.completedAt.isSmallerThanValue(weekEnd),
          ))
        .watch()
        .map((logs) {
      final result = <int, int>{};
      for (final log in logs) {
        result[log.habitId] = (result[log.habitId] ?? 0) + 1;
      }
      return result;
    });
  }

  Future<List<HabitLog>> getLogsForHabit(int habitId,
      {DateTime? from, DateTime? to}) {
    final query = select(habitLogs)
      ..where((l) => l.habitId.equals(habitId));
    if (from != null) {
      query.where((l) => l.completedAt.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where((l) => l.completedAt.isSmallerThanValue(to));
    }
    return query.get();
  }

  Stream<List<HabitLog>> watchAllHabitLogs() => select(habitLogs).watch();

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
}
