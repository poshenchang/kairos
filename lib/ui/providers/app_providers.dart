// lib/ui/providers/app_providers.dart
//
// Application-level state providers for categories, events, tasks, habits,
// and smart dashboard suggestions.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';

// ── Categories ──────────────────────────────────────────────────────────────

final allCategoriesProvider = StreamProvider<List<Category>>((ref) {
  final dao = ref.watch(categoryDaoProvider);
  return dao.watchAllCategories();
});

// ── Events ──────────────────────────────────────────────────────────────────

final todayEventsProvider = StreamProvider<List<Event>>((ref) {
  final dao = ref.watch(eventDaoProvider);
  return dao.watchEventsForDay(DateTime.now());
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

// ── Habits ──────────────────────────────────────────────────────────────────

final activeHabitsProvider = StreamProvider<List<Habit>>((ref) {
  final dao = ref.watch(habitDaoProvider);
  return dao.watchActiveHabits();
});

final weeklyHabitCompletionsProvider = FutureProvider<Map<int, int>>((ref) async {
  final dao = ref.watch(habitDaoProvider);
  final now = DateTime.now();
  final monday = now.subtract(Duration(days: now.weekday - 1));
  final weekStart = DateTime.utc(monday.year, monday.month, monday.day);
  final weekEnd = weekStart.add(const Duration(days: 7));
  return dao.getWeeklyCompletions(weekStart, weekEnd);
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

  // Find the next upcoming event today
  final upcomingEvents = todayEvents
      .where((e) => e.startTime.isAfter(now))
      .toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));

  final nextEvent = upcomingEvents.isNotEmpty ? upcomingEvents.first : null;
  final freeUntil = nextEvent?.startTime ?? DateTime(now.year, now.month, now.day, 22, 0);
  final freeMinutes = freeUntil.difference(now).inMinutes;

  if (freeMinutes < 15) {
    if (nextEvent != null) {
      return SmartSuggestion(
        freeDuration: Duration(minutes: freeMinutes.clamp(0, 15)),
        title: 'Upcoming: ${nextEvent.title}',
        description: 'Starts in $freeMinutes minutes. Prepare your materials.',
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

