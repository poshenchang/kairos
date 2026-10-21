// lib/services/weekly_stats.dart
//
// Habit streaks and the "last week" review. Pure functions over wall-clock
// times in the user's active timezone; weeks start on Sunday, matching
// weeklyHabitCompletionsProvider.

import 'package:kairos/data/database/app_database.dart';

DateTime _day(DateTime t) => DateTime(t.year, t.month, t.day);

/// Sunday that starts the week containing [t].
DateTime weekStart(DateTime t) => _day(t).subtract(Duration(days: t.weekday % 7));

bool _countsForHabit(Habit habit, DateTime day) => switch (habit.daysFilter) {
      'weekdays' => day.weekday <= DateTime.friday,
      'weekends' => day.weekday >= DateTime.saturday,
      _ => true,
    };

/// Current streak for [habit] given its session times [logTimes].
///
/// Daily habits (7×/week) count consecutive days with a session, skipping
/// days excluded by the habit's day filter. Other habits count consecutive
/// weeks that met the weekly target. Today / this week only extends the
/// streak; not having finished it yet doesn't break it.
int habitStreak(Habit habit, Iterable<DateTime> logTimes, DateTime now) {
  if (habit.targetFrequencyPerWeek >= 7) {
    final days = logTimes.map(_day).toSet();
    var cursor = _day(now);
    if (!days.contains(cursor)) cursor = cursor.subtract(const Duration(days: 1));
    var streak = 0;
    // Bounded walk back; a year of skipped filter days can't loop forever
    for (var i = 0; i < 3660; i++) {
      if (!_countsForHabit(habit, cursor)) {
        cursor = cursor.subtract(const Duration(days: 1));
        continue;
      }
      if (!days.contains(cursor)) break;
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  final perWeek = <DateTime, int>{};
  for (final t in logTimes) {
    final w = weekStart(t);
    perWeek[w] = (perWeek[w] ?? 0) + 1;
  }
  bool met(DateTime week) => (perWeek[week] ?? 0) >= habit.targetFrequencyPerWeek;

  var week = weekStart(now);
  if (!met(week)) week = week.subtract(const Duration(days: 7));
  var streak = 0;
  while (met(week)) {
    streak++;
    week = week.subtract(const Duration(days: 7));
  }
  return streak;
}

class WeeklyReview {
  /// Sunday that started the week being reviewed.
  final DateTime weekStart;
  final int tasksCompleted;
  final int habitsOnTarget;
  final int habitsTotal;
  final List<Task> overdueTasks;

  const WeeklyReview({
    required this.weekStart,
    required this.tasksCompleted,
    required this.habitsOnTarget,
    required this.habitsTotal,
    required this.overdueTasks,
  });
}

/// Summary of the week before the one containing [now].
///
/// [toWallTime] converts stored UTC timestamps to the active timezone.
/// Recurring tasks don't keep a completion record (completing one advances
/// its due date), so only one-off completions are counted.
WeeklyReview buildWeeklyReview({
  required DateTime now,
  required List<Task> tasks,
  required List<Habit> activeHabits,
  required List<HabitLog> logs,
  required DateTime Function(DateTime utc) toWallTime,
}) {
  final thisWeek = weekStart(now);
  final lastWeek = thisWeek.subtract(const Duration(days: 7));
  bool inLastWeek(DateTime wall) => !wall.isBefore(lastWeek) && wall.isBefore(thisWeek);

  final completed = tasks.where((t) => t.isCompleted && t.completedAt != null && inLastWeek(toWallTime(t.completedAt!))).length;

  final logsPerHabit = <int, int>{};
  for (final l in logs) {
    if (inLastWeek(toWallTime(l.completedAt))) logsPerHabit[l.habitId] = (logsPerHabit[l.habitId] ?? 0) + 1;
  }
  final onTarget = activeHabits.where((h) => (logsPerHabit[h.id] ?? 0) >= h.targetFrequencyPerWeek).length;

  final overdue = tasks.where((t) => !t.isCompleted && toWallTime(t.dueDate).isBefore(now)).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  return WeeklyReview(
    weekStart: lastWeek,
    tasksCompleted: completed,
    habitsOnTarget: onTarget,
    habitsTotal: activeHabits.length,
    overdueTasks: overdue,
  );
}
