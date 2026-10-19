// lib/ui/providers/app_providers.dart
//
// Application-level state providers for categories, events, tasks, habits,
// and smart dashboard suggestions.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';

// ── Categories ──────────────────────────────────────────────────────────────

final allCategoriesProvider = StreamProvider<List<Category>>((ref) {
  final dao = ref.watch(categoryDaoProvider);
  return dao.watchAllCategories();
});

// ── Events ──────────────────────────────────────────────────────────────────

final todayEventsProvider = FutureProvider<List<Event>>((ref) async {
  final repo = ref.watch(eventRepositoryProvider);
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 1));
  return repo.getExpandedEventsInRange(start, end);
});

final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

final selectedDateEventsProvider = FutureProvider<List<Event>>((ref) async {
  final date = ref.watch(selectedDateProvider);
  final repo = ref.watch(eventRepositoryProvider);
  final start = DateTime(date.year, date.month, date.day);
  final end = start.add(const Duration(days: 1));
  return repo.getExpandedEventsInRange(start, end);
});

final weekEventsProvider = FutureProvider.family<List<Event>, DateTime>((ref, weekStart) async {
  final repo = ref.watch(eventRepositoryProvider);
  final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
  final end = start.add(const Duration(days: 7));
  return repo.getExpandedEventsInRange(start, end);
});

final allEventsStreamProvider = StreamProvider<List<Event>>((ref) {
  final dao = ref.watch(eventDaoProvider);
  return dao.watchAllEvents();
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

final activeHabitsProvider = StreamProvider<List<Habit>>((ref) {
  final dao = ref.watch(habitDaoProvider);
  return dao.watchActiveHabits();
});

final habitCompletionsForWeekProvider = FutureProvider.family<Map<int, int>, DateTime>((ref, weekSunday) async {
  final dao = ref.watch(habitDaoProvider);
  final start = DateTime.utc(weekSunday.year, weekSunday.month, weekSunday.day);
  final end = start.add(const Duration(days: 7));
  return dao.getWeeklyCompletions(start, end);
});

final weeklyHabitCompletionsProvider = FutureProvider<Map<int, int>>((ref) async {
  final now = DateTime.now();
  final daysBack = now.weekday % 7; // Sunday start (Sunday = weekday 7 % 7 = 0)
  final sunday = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysBack));
  return ref.watch(habitCompletionsForWeekProvider(sunday).future);
});

// ── Smart Free Time & Suggestion ─────────────────────────────────────────────

class SmartSuggestion {
  final Duration freeDuration;
  final String title;
  final String description;
  final String actionLabel;
  final String category;
  final bool hasFreeTime;

  const SmartSuggestion({
    required this.freeDuration,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.category,
    required this.hasFreeTime,
  });
}

final smartSuggestionProvider = Provider<SmartSuggestion>((ref) {
  final todayEventsAsync = ref.watch(todayEventsProvider);
  final tasksAsync = ref.watch(incompleteTasksStreamProvider);
  final habitsAsync = ref.watch(activeHabitsProvider);
  final habitCountsAsync = ref.watch(weeklyHabitCompletionsProvider);

  final now = DateTime.now();
  final todayEvents = todayEventsAsync.value ?? [];
  final tasks = tasksAsync.value ?? [];
  final habits = habitsAsync.value ?? [];
  final habitCounts = habitCountsAsync.value ?? {};

  // 1. Check if user is CURRENTLY in an event right now according to the timetable
  final currentEvents = todayEvents.where((e) {
    if (e.isDeleted || e.eventType == 'reminder') return false;
    final start = e.startTime.toLocal();
    final end = e.endTime.toLocal();
    return !now.isBefore(start) && now.isBefore(end);
  }).toList()
    ..sort((a, b) => b.endTime.compareTo(a.endTime));

  if (currentEvents.isNotEmpty) {
    final currentEvent = currentEvents.first;
    final remainingMinutes = currentEvent.endTime.toLocal().difference(now).inMinutes;
    final endFormatted = DateFormat('h:mm a').format(currentEvent.endTime.toLocal());

    // Check what to do after current event ends
    final afterEvents = todayEvents.where((e) {
      if (e.isDeleted || e.eventType == 'reminder') return false;
      return !e.startTime.toLocal().isBefore(currentEvent.endTime.toLocal());
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final nextAfter = afterEvents.isNotEmpty ? afterEvents.first : null;
    String whatNextText;
    if (nextAfter != null) {
      final gap = nextAfter.startTime.toLocal().difference(currentEvent.endTime.toLocal()).inMinutes;
      final startFmt = DateFormat('h:mm a').format(nextAfter.startTime.toLocal());
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
      .where((e) => !e.isDeleted && e.eventType != 'reminder' && e.startTime.toLocal().isAfter(now))
      .toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));

  final nextEvent = upcomingEvents.isNotEmpty ? upcomingEvents.first : null;
  final freeUntil = nextEvent?.startTime.toLocal() ?? DateTime(now.year, now.month, now.day, 22, 0);
  final freeMinutes = freeUntil.difference(now).inMinutes;

  if (freeMinutes < 15) {
    if (nextEvent != null) {
      return SmartSuggestion(
        freeDuration: Duration(minutes: freeMinutes.clamp(0, 15)),
        title: 'Upcoming: ${nextEvent.title}',
        description: 'Starts in $freeMinutes minutes (${DateFormat('h:mm a').format(nextEvent.startTime.toLocal())}). Prepare your materials.',
        actionLabel: 'View Event',
        category: nextEvent.category,
        hasFreeTime: false,
      );
    }
    return const SmartSuggestion(
      freeDuration: Duration.zero,
      title: 'Rest & Recharge',
      description: 'No active events right now. Take a short breather.',
      actionLabel: 'Check Tomorrow',
      category: 'personal',
      hasFreeTime: false,
    );
  }

  // Look for most urgent task
  final urgentTasks = tasks
      .where((t) => t.dueDate.isAfter(now) || t.dueDate.isBefore(now))
      .toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));

  if (urgentTasks.isNotEmpty) {
    final topTask = urgentTasks.first;
    final hoursLeft = topTask.dueDate.difference(now).inHours;
    final urgencyText = topTask.dueDate.isBefore(now)
        ? 'Overdue!'
        : hoursLeft < 24
            ? 'Due in ${hoursLeft}h'
            : 'Due soon';

    return SmartSuggestion(
      freeDuration: Duration(minutes: freeMinutes),
      title: 'Focus: ${topTask.title}',
      description: 'You have ${freeMinutes ~/ 60}h ${freeMinutes % 60}m free. $urgencyText.',
      actionLabel: 'Start Focus Timer (25m)',
      category: topTask.category,
      hasFreeTime: true,
    );
  }

  // Look for habits that need attention this week
  final pendingHabits = habits.where((h) {
    final completed = habitCounts[h.id] ?? 0;
    return completed < h.targetFrequencyPerWeek;
  }).toList();

  if (pendingHabits.isNotEmpty) {
    final habit = pendingHabits.first;
    final completed = habitCounts[habit.id] ?? 0;
    return SmartSuggestion(
      freeDuration: Duration(minutes: freeMinutes),
      title: 'Habit: ${habit.title}',
      description: 'You have free time! $completed/${habit.targetFrequencyPerWeek} sessions done this week.',
      actionLabel: 'Log Session or Start Timer',
      category: habit.category,
      hasFreeTime: true,
    );
  }

  return SmartSuggestion(
    freeDuration: Duration(minutes: freeMinutes),
    title: 'Great job! You\'re all caught up',
    description: 'You have ${freeMinutes ~/ 60}h ${freeMinutes % 60}m of open time today.',
    actionLabel: 'Plan Ahead',
    category: 'personal',
    hasFreeTime: true,
  );
});

