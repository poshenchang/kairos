// lib/ui/providers/app_providers.dart
//
// Application-level state providers for categories, events, tasks, habits,
// and smart dashboard suggestions.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/timezone_service.dart';

// ── Categories ──────────────────────────────────────────────────────────────

final allCategoriesProvider = StreamProvider<List<Category>>((ref) {
  final dao = ref.watch(categoryDaoProvider);
  return dao.watchAllCategories();
});

// ── Events ──────────────────────────────────────────────────────────────────

final allEventsStreamProvider = StreamProvider<List<Event>>((ref) {
  final dao = ref.watch(eventDaoProvider);
  return dao.watchAllEvents();
});

final todayEventsProvider = FutureProvider<List<Event>>((ref) async {
  final repo = ref.watch(eventRepositoryProvider);
  final settings = ref.read(settingsNotifierProvider);
  final now = TimezoneService.instance.activeNow(settings);
  final startWall = DateTime(now.year, now.month, now.day);
  final endWall = startWall.add(const Duration(days: 1));
  final startUtc = TimezoneService.instance.fromActiveTime(startWall, settings);
  final endUtc = TimezoneService.instance.fromActiveTime(endWall, settings);
  return repo.getExpandedEventsInRange(startUtc, endUtc);
});

final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

final selectedDateEventsProvider = FutureProvider<List<Event>>((ref) async {
  final date = ref.watch(selectedDateProvider);
  final repo = ref.watch(eventRepositoryProvider);
  final settings = ref.read(settingsNotifierProvider);
  final startWall = DateTime(date.year, date.month, date.day);
  final endWall = startWall.add(const Duration(days: 1));
  final startUtc = TimezoneService.instance.fromActiveTime(startWall, settings);
  final endUtc = TimezoneService.instance.fromActiveTime(endWall, settings);
  return repo.getExpandedEventsInRange(startUtc, endUtc);
});

final weekEventsProvider = FutureProvider.family<List<Event>, DateTime>((ref, weekStart) async {
  final repo = ref.watch(eventRepositoryProvider);
  final settings = ref.read(settingsNotifierProvider);
  final startWall = DateTime(weekStart.year, weekStart.month, weekStart.day);
  final endWall = startWall.add(const Duration(days: 7));
  final startUtc = TimezoneService.instance.fromActiveTime(startWall, settings);
  final endUtc = TimezoneService.instance.fromActiveTime(endWall, settings);
  return repo.getExpandedEventsInRange(startUtc, endUtc);
});

final holidaysForDateProvider = FutureProvider.family<List<Holiday>, DateTime>((ref, date) async {
  final dao = ref.watch(holidayDaoProvider);
  return dao.getHolidaysForDate(date);
});

// ── Tasks ───────────────────────────────────────────────────────────────────

final incompleteTasksStreamProvider = StreamProvider<List<Task>>((ref) {
  final dao = ref.watch(taskDaoProvider);
  return dao.watchIncompleteTasks();
});

/// Returns incomplete tasks with recurring tasks collapsed to only their next occurrence.
final dashboardTasksProvider = FutureProvider<List<Task>>((ref) async {
  // Re-run when the raw tasks stream emits
  ref.watch(incompleteTasksStreamProvider);
  final repo = ref.watch(taskRepositoryProvider);
  return repo.getDashboardTasks();
});

final subtasksForTaskProvider = StreamProvider.family<List<Subtask>, int>((ref, taskId) {
  final dao = ref.watch(taskDaoProvider);
  return dao.watchSubtasksForTask(taskId);
});

// ── Habits ──────────────────────────────────────────────────────────────────

final allHabitLogsStreamProvider = StreamProvider<List<HabitLog>>((ref) {
  final dao = ref.watch(habitDaoProvider);
  return dao.watchAllHabitLogs();
});

final activeHabitsProvider = StreamProvider<List<Habit>>((ref) {
  final dao = ref.watch(habitDaoProvider);
  return dao.watchActiveHabits();
});

final habitCompletionsForWeekProvider = StreamProvider.family<Map<int, int>, DateTime>((ref, weekSunday) {
  final dao = ref.watch(habitDaoProvider);
  final start = DateTime(weekSunday.year, weekSunday.month, weekSunday.day);
  final end = start.add(const Duration(days: 7));
  return dao.watchWeeklyCompletions(start, end);
});

final weeklyHabitCompletionsProvider = StreamProvider<Map<int, int>>((ref) {
  final dao = ref.watch(habitDaoProvider);
  final now = DateTime.now();
  final daysBack = now.weekday % 7; // Sunday start (Sunday = weekday 7 % 7 = 0)
  final sunday = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysBack));
  final start = DateTime(sunday.year, sunday.month, sunday.day);
  final end = start.add(const Duration(days: 7));
  return dao.watchWeeklyCompletions(start, end);
});

final todayHabitCompletionsProvider = StreamProvider<Map<int, int>>((ref) {
  final dao = ref.watch(habitDaoProvider);
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 1));
  return dao.watchWeeklyCompletions(start, end);
});

// ── Smart Free Time & Suggestion ─────────────────────────────────────────────

class SmartSuggestion {
  final Duration freeDuration;
  final String title;
  final String description;
  final String actionLabel;
  final String category;
  final bool hasFreeTime;
  final Task? task;
  final Habit? habit;

  const SmartSuggestion({
    required this.freeDuration,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.category,
    required this.hasFreeTime,
    this.task,
    this.habit,
  });
}

final smartSuggestionProvider = Provider<SmartSuggestion>((ref) {
  final todayEventsAsync = ref.watch(todayEventsProvider);
  final tasksAsync = ref.watch(incompleteTasksStreamProvider);
  final habitsAsync = ref.watch(activeHabitsProvider);
  final habitCountsAsync = ref.watch(weeklyHabitCompletionsProvider);
  final todayHabitCountsAsync = ref.watch(todayHabitCompletionsProvider);

  final settings = ref.watch(settingsNotifierProvider);
  final now = TimezoneService.instance.activeNow(settings);
  final todayEvents = todayEventsAsync.value ?? [];
  final tasks = tasksAsync.value ?? [];
  final habits = habitsAsync.value ?? [];
  final habitCounts = habitCountsAsync.value ?? {};
  final todayHabitCounts = todayHabitCountsAsync.value ?? {};

  // 1. Check if user is CURRENTLY in an event right now according to the timetable
  final currentEvents = todayEvents.where((e) {
    if (e.isDeleted || e.eventType == 'reminder') return false;
    final start = TimezoneService.instance.toActiveTime(e.startTime, settings);
    final end = TimezoneService.instance.toActiveTime(e.endTime, settings);
    return !now.isBefore(start) && now.isBefore(end);
  }).toList()
    ..sort((a, b) => b.endTime.compareTo(a.endTime));

  if (currentEvents.isNotEmpty) {
    final currentEvent = currentEvents.first;
    final currentEnd = TimezoneService.instance.toActiveTime(currentEvent.endTime, settings);
    final remainingMinutes = currentEnd.difference(now).inMinutes;
    final endFormatted = DateFormat('h:mm a').format(currentEnd);

    // Check what to do after current event ends
    final afterEvents = todayEvents.where((e) {
      if (e.isDeleted || e.eventType == 'reminder') return false;
      final start = TimezoneService.instance.toActiveTime(e.startTime, settings);
      return !start.isBefore(currentEnd);
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final nextAfter = afterEvents.isNotEmpty ? afterEvents.first : null;
    String whatNextText;
    if (nextAfter != null) {
      final nextStart = TimezoneService.instance.toActiveTime(nextAfter.startTime, settings);
      final gap = nextStart.difference(currentEnd).inMinutes;
      final startFmt = DateFormat('h:mm a').format(nextStart);
      if (gap <= 5) {
        whatNextText = 'Followed immediately by "${nextAfter.title}" at $startFmt.';
      } else {
        whatNextText = 'Next: "${nextAfter.title}" at $startFmt (${gap}m break).';
      }
    } else {
      whatNextText = 'Open time after this event ends.';
    }

    return SmartSuggestion(
      freeDuration: Duration.zero,
      title: 'In Event: ${currentEvent.title}',
      description: 'Ends at $endFormatted (${remainingMinutes}m remaining). $whatNextText',
      actionLabel: 'View Schedule',
      category: currentEvent.category,
      hasFreeTime: false,
    );
  }

  // 2. User is NOT currently in an event. Look for the next upcoming event today.
  final upcomingEvents = todayEvents
      .where((e) {
        if (e.isDeleted || e.eventType == 'reminder') return false;
        final start = TimezoneService.instance.toActiveTime(e.startTime, settings);
        return start.isAfter(now);
      })
      .toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));

  final nextEvent = upcomingEvents.isNotEmpty ? upcomingEvents.first : null;
  final nextEventStart = nextEvent != null
      ? TimezoneService.instance.toActiveTime(nextEvent.startTime, settings)
      : null;
  final freeMinutes = nextEventStart != null
      ? nextEventStart.difference(now).inMinutes
      : 120;

  if (nextEvent != null && freeMinutes < 15) {
    return SmartSuggestion(
      freeDuration: Duration(minutes: freeMinutes.clamp(0, 15)),
      title: 'Upcoming: ${nextEvent.title}',
      description: 'Starts in $freeMinutes minutes (${DateFormat('h:mm a').format(nextEventStart!)}). Prepare your materials.',
      actionLabel: 'View Event',
      category: nextEvent.category,
      hasFreeTime: false,
    );
  }

  // 3. User HAS free time (>= 15 minutes).
  // Prioritize habits and tasks with closest deadlines, including uncompleted daily habits.
  final freeText = '${freeMinutes ~/ 60 > 0 ? '${freeMinutes ~/ 60}h ' : ''}${freeMinutes % 60}m';

  final candidates = <_CandidateItem>[];

  // A. Check incomplete tasks
  for (final task in tasks) {
    final due = TimezoneService.instance.toActiveTime(task.dueDate, settings);
    if (due.isBefore(now)) {
      // Overdue task
      final diff = now.difference(due);
      final hoursOverdue = (diff.inMinutes / 60).round();
      final urgencyText = diff.inMinutes < 5
          ? 'Overdue!'
          : hoursOverdue < 24
              ? 'Overdue by ${hoursOverdue}h!'
              : 'Overdue by ${(diff.inHours / 24).round()}d!';
      candidates.add(
        _CandidateItem(
          effectiveDeadline: due,
          priorityRank: 1, // Overdue tasks have highest priority
          suggestion: SmartSuggestion(
            freeDuration: Duration(minutes: freeMinutes),
            title: 'Focus: ${task.title}',
            description: 'You have $freeText free. $urgencyText (was due ${DateFormat('MMM d, h:mm a').format(due)}).',
            actionLabel: 'Start Focus Timer (25m)',
            category: task.category,
            hasFreeTime: true,
            task: task,
          ),
        ),
      );
    } else {
      // Future task
      final diff = due.difference(now);
      final hoursUntil = (diff.inMinutes / 60).round();
      final minutesUntil = diff.inMinutes;

      int rank;
      String urgencyText;
      if (diff.inHours < 3) {
        rank = 2; // Imminent task due within 3 hours
        urgencyText = hoursUntil == 0
            ? 'Due in ${minutesUntil}m (${DateFormat('h:mm a').format(due)})'
            : 'Due in ${hoursUntil}h (${DateFormat('h:mm a').format(due)})';
      } else if (diff.inHours < 24) {
        rank = 3; // Due within 24 hours
        urgencyText = hoursUntil == 0
            ? 'Due in ${minutesUntil}m (${DateFormat('h:mm a').format(due)})'
            : 'Due in ${hoursUntil}h (${DateFormat('h:mm a').format(due)})';
      } else if (diff.inHours < 72) {
        final days = (diff.inHours / 24).round();
        rank = 5; // Due within 3 days
        urgencyText = 'Due in ${days}d (${DateFormat('EEE, h:mm a').format(due)})';
      } else {
        rank = 7; // Due later
        urgencyText = 'Due ${DateFormat('MMM d').format(due)}';
      }

      candidates.add(
        _CandidateItem(
          effectiveDeadline: due,
          priorityRank: rank,
          suggestion: SmartSuggestion(
            freeDuration: Duration(minutes: freeMinutes),
            title: 'Focus: ${task.title}',
            description: 'You have $freeText free. $urgencyText.',
            actionLabel: 'Start Focus Timer (25m)',
            category: task.category,
            hasFreeTime: true,
            task: task,
          ),
        ),
      );
    }
  }

  // B. Check active habits
  final isWeekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
  final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

  // End of current week (Sunday 23:59:59)
  final daysUntilSunday = (7 - (now.weekday % 7)) % 7;
  final weekEnd = DateTime(now.year, now.month, now.day + daysUntilSunday, 23, 59, 59);

  for (final habit in habits) {
    // Days filter check
    if (habit.daysFilter == 'weekdays' && isWeekend) continue;
    if (habit.daysFilter == 'weekends' && !isWeekend) continue;

    final isDaily = habit.targetFrequencyPerWeek >= 7;
    final completedToday = todayHabitCounts[habit.id] ?? 0;
    final completedThisWeek = habitCounts[habit.id] ?? 0;

    if (isDaily && completedToday == 0) {
      // Uncompleted daily habit! Effective deadline is end of today.
      Event? scheduledLater;
      for (final e in todayEvents) {
        final start = TimezoneService.instance.toActiveTime(e.startTime, settings);
        if (!e.isDeleted &&
            start.isAfter(now) &&
            e.autoScheduleSource != null &&
            e.autoScheduleSource!.contains('habit:${habit.id}')) {
          scheduledLater = e;
          break;
        }
      }

      final String desc;
      final int rank;
      if (scheduledLater != null) {
        rank = 4;
        final start = TimezoneService.instance.toActiveTime(scheduledLater.startTime, settings);
        final timeStr = DateFormat('h:mm a').format(start);
        desc = 'You have $freeText free. Daily habit scheduled for $timeStr, or get ahead now.';
      } else {
        rank = 3; // Unscheduled daily habit is urgent for today
        desc = 'You have $freeText free. Daily habit not yet completed today.';
      }

      candidates.add(
        _CandidateItem(
          effectiveDeadline: todayEnd,
          priorityRank: rank,
          suggestion: SmartSuggestion(
            freeDuration: Duration(minutes: freeMinutes),
            title: 'Daily Habit: ${habit.title}',
            description: desc,
            actionLabel: 'Log Session or Focus',
            category: habit.category,
            hasFreeTime: true,
            habit: habit,
          ),
        ),
      );
    } else if (!isDaily && completedThisWeek < habit.targetFrequencyPerWeek) {
      // Uncompleted weekly habit! Effective deadline is end of week.
      candidates.add(
        _CandidateItem(
          effectiveDeadline: weekEnd,
          priorityRank: 6,
          suggestion: SmartSuggestion(
            freeDuration: Duration(minutes: freeMinutes),
            title: 'Habit: ${habit.title}',
            description: 'You have $freeText free. $completedThisWeek/${habit.targetFrequencyPerWeek} sessions done this week.',
            actionLabel: 'Log Session or Focus',
            category: habit.category,
            hasFreeTime: true,
            habit: habit,
          ),
        ),
      );
    }
  }

  if (candidates.isNotEmpty) {
    candidates.sort((a, b) {
      final rankCmp = a.priorityRank.compareTo(b.priorityRank);
      if (rankCmp != 0) return rankCmp;
      return a.effectiveDeadline.compareTo(b.effectiveDeadline);
    });

    return candidates.first.suggestion;
  }

  return SmartSuggestion(
    freeDuration: Duration(minutes: freeMinutes),
    title: 'Great job! You\'re all caught up',
    description: 'You have $freeText of open time today.',
    actionLabel: 'Plan Ahead',
    category: 'personal',
    hasFreeTime: true,
  );
});

class _CandidateItem {
  final DateTime effectiveDeadline;
  final int priorityRank;
  final SmartSuggestion suggestion;

  _CandidateItem({
    required this.effectiveDeadline,
    required this.priorityRank,
    required this.suggestion,
  });
}

