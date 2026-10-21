// test/services/weekly_stats_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/services/weekly_stats.dart';

Habit _habit({int id = 1, int target = 7, String daysFilter = 'all'}) => Habit(
      id: id,
      title: 'h$id',
      category: 'personal',
      targetFrequencyPerWeek: target,
      minSessionMinutes: 30,
      maxSessionMinutes: 60,
      preferredWindow: 'any',
      daysFilter: daysFilter,
      isActive: true,
      isDeleted: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

Task _task(String title, {required DateTime due, bool completed = false, DateTime? completedAt}) => Task(
      id: title.hashCode,
      title: title,
      category: 'schoolwork',
      dueDate: due,
      priority: 3,
      isRecurring: false,
      isCompleted: completed,
      completedAt: completedAt,
      isDeleted: false,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

HabitLog _log(int habitId, DateTime at) => HabitLog(
      id: at.hashCode,
      habitId: habitId,
      completedAt: at,
      isDeleted: false,
      createdAt: at,
      updatedAt: at,
    );

void main() {
  // Wednesday, Oct 21 2026, 14:00. Week started Sunday Oct 18.
  final now = DateTime(2026, 10, 21, 14);
  DateTime oct(int day, [int hour = 9]) => DateTime(2026, 10, day, hour);

  test('weekStart is the preceding Sunday', () {
    expect(weekStart(now), DateTime(2026, 10, 18));
    expect(weekStart(DateTime(2026, 10, 18, 23)), DateTime(2026, 10, 18));
  });

  group('daily streak', () {
    test('counts back from today, and today not done yet does not break it', () {
      expect(habitStreak(_habit(), [oct(21), oct(20), oct(19), oct(17)], now), 3);
      expect(habitStreak(_habit(), [oct(20), oct(19)], now), 2);
    });

    test('a missed day breaks it', () {
      expect(habitStreak(_habit(), [oct(21), oct(19)], now), 1);
      expect(habitStreak(_habit(), [], now), 0);
    });

    test('weekday-only habits skip weekends', () {
      // Fri 16, (Sat/Sun skipped), Mon 19, Tue 20, Wed 21
      final logs = [oct(16), oct(19), oct(20), oct(21)];
      expect(habitStreak(_habit(daysFilter: 'weekdays'), logs, now), 4);
      expect(habitStreak(_habit(), logs, now), 3);
    });
  });

  group('weekly streak', () {
    test('counts consecutive weeks meeting the target', () {
      final logs = [oct(5), oct(7), oct(12), oct(14), oct(19)];
      // Weeks of Oct 4 and Oct 11 met 2×; current week has 1 so far
      expect(habitStreak(_habit(target: 2), logs, now), 2);
      expect(habitStreak(_habit(target: 2), [...logs, oct(20)], now), 3);
    });

    test('a missed week breaks it', () {
      expect(habitStreak(_habit(target: 2), [oct(5), oct(7), oct(19), oct(20)], now), 1);
    });
  });

  test('weekly review summarises the previous Sunday–Saturday', () {
    final review = buildWeeklyReview(
      now: now,
      tasks: [
        _task('done last week', due: oct(15), completed: true, completedAt: oct(14)),
        _task('done this week', due: oct(20), completed: true, completedAt: oct(19)),
        _task('overdue', due: oct(20)),
        _task('upcoming', due: oct(25)),
      ],
      activeHabits: [_habit(id: 1, target: 2), _habit(id: 2, target: 3)],
      logs: [_log(1, oct(12)), _log(1, oct(13)), _log(2, oct(12)), _log(1, oct(19))],
      toWallTime: (t) => t,
    );

    expect(review.weekStart, DateTime(2026, 10, 11));
    expect(review.tasksCompleted, 1);
    expect(review.habitsOnTarget, 1);
    expect(review.habitsTotal, 2);
    expect(review.overdueTasks.map((t) => t.title), ['overdue']);
  });
}
