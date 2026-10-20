// lib/ui/screens/dashboard/dashboard_screen.dart
//
// Main Dashboard: Hero Suggestion, Deadlines, Today's Timeline, Habits.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/habit_suggestion_service.dart';
import 'package:kairos/services/notification_service.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/timezone_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/widgets/add_event_dialog.dart';
import 'package:kairos/ui/widgets/add_task_dialog.dart';
import 'package:kairos/ui/widgets/edit_event_dialog.dart';
import 'package:kairos/ui/widgets/edit_task_dialog.dart';
import 'package:kairos/ui/widgets/edit_habit_dialog.dart';
import 'package:kairos/ui/widgets/category_badge.dart';
import 'package:kairos/ui/widgets/focus_timer_dialog.dart';
import 'package:kairos/ui/widgets/log_habit_dialog.dart';
import 'package:kairos/ui/widgets/app_global_actions.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsNotifierProvider);
    final now = TimezoneService.instance.activeNow(settings);
    final suggestion = ref.watch(smartSuggestionProvider);
    final todayEventsAsync = ref.watch(todayEventsProvider);
    final dashboardTasksAsync = ref.watch(dashboardTasksProvider);
    final activeHabitsAsync = ref.watch(activeHabitsProvider);
    final habitCountsAsync = ref.watch(weeklyHabitCompletionsProvider);
    final categories = ref.watch(allCategoriesProvider).value ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kairos',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
            ),
            Text(
              DateFormat('EEEE, MMMM d').format(now),
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: const [
          AppGlobalActions(),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          final db = ref.read(appDatabaseProvider);
          final settings = ref.read(settingsNotifierProvider);
          final notificationService = ref.read(notificationServiceProvider);
          await HabitSuggestionService.instance.runPeriodicChecks(
            db: db,
            settings: settings,
            notificationService: notificationService,
          );
          ref.invalidate(todayEventsProvider);
          ref.invalidate(dashboardTasksProvider);
          ref.invalidate(activeHabitsProvider);
          ref.invalidate(weeklyHabitCompletionsProvider);
          ref.invalidate(todayHabitCompletionsProvider);
        },

        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. SMART SUGGESTION HERO CARD (Eliminates idle hesitation)
              _buildSuggestionHero(context, ref, suggestion),

              const SizedBox(height: 24),

              // 2. UPCOMING DEADLINES / TASKS (Filter for next occurrence only)
              _buildDeadlinesSection(context, ref, dashboardTasksAsync),

              const SizedBox(height: 24),

              // 3. TODAY'S SCHEDULE (Events, Prep blocks, Commutes)
              _buildTodayTimeline(context, ref, todayEventsAsync, categories),

              const SizedBox(height: 24),

              // 4. HABITS PROGRESS THIS WEEK
              _buildHabitsSection(context, ref, activeHabitsAsync, habitCountsAsync),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestionHero(
    BuildContext context,
    WidgetRef ref,
    SmartSuggestion suggestion,
  ) {
    final (gradientColors, shadowColor, badgeIcon, defaultBadgeLabel, btnColor) = switch (suggestion.period) {
      SmartSuggestionPeriod.night => (
        [const Color(0xFF0F172A), const Color(0xFF1E1B4B)],
        const Color(0xFF1E1B4B).withValues(alpha: 0.4),
        Icons.bedtime_outlined,
        'REWIND & WIND DOWN',
        const Color(0xFF1E1B4B),
      ),
      SmartSuggestionPeriod.morning => (
        [const Color(0xFFD97706), const Color(0xFF4F46E5)],
        const Color(0xFFD97706).withValues(alpha: 0.35),
        Icons.wb_sunny_outlined,
        'GET READY FOR THE DAY',
        const Color(0xFFB45309),
      ),
      SmartSuggestionPeriod.daytime => (
        [const Color(0xFF2563EB), const Color(0xFF4F46E5)],
        const Color(0xFF2563EB).withValues(alpha: 0.3),
        Icons.lightbulb_outline,
        'WHAT TO DO NEXT',
        const Color(0xFF2563EB),
      ),
    };

    final isCalendarAction = suggestion.actionLabel.contains('Agenda') ||
        suggestion.actionLabel.contains('Schedule') ||
        suggestion.actionLabel.contains('Calendar') ||
        suggestion.actionLabel.contains('Plan');

    final primaryIcon = switch (suggestion.period) {
      SmartSuggestionPeriod.night => isCalendarAction ? Icons.calendar_month : Icons.play_arrow,
      SmartSuggestionPeriod.morning => isCalendarAction ? Icons.calendar_month : Icons.play_arrow,
      SmartSuggestionPeriod.daytime => suggestion.hasFreeTime ? Icons.play_arrow : Icons.calendar_today,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(badgeIcon, color: Colors.amberAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                suggestion.badgeLabel ?? defaultBadgeLabel,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              CategoryBadge(categorySlugOrName: suggestion.category, compact: true),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            suggestion.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            suggestion.description,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          if (suggestion.quote != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.format_quote, color: Colors.amberAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '“${suggestion.quote!}”',
                          style: const TextStyle(
                            color: Colors.white,
                            fontStyle: FontStyle.italic,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                        if (suggestion.quoteAuthor != null && suggestion.quoteAuthor!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '— ${suggestion.quoteAuthor!}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: Icon(primaryIcon, size: 18),
                label: Text(suggestion.actionLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: btnColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () {
                  if (isCalendarAction || !suggestion.hasFreeTime) {
                    context.go('/calendar');
                  } else {
                    FocusTimerDialog.show(
                      context,
                      title: suggestion.title,
                      category: suggestion.category,
                      defaultMinutes: 25,
                    );
                  }
                },
              ),
              if (suggestion.habit != null) ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.check_circle_outline, color: Colors.white, size: 16),
                  label: const Text('Log Session', style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onPressed: () {
                    LogHabitDialog.show(context, suggestion.habit!);
                  },
                ),
              ],
              if (!isCalendarAction)
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month, color: Colors.white, size: 16),
                  label: const Text('View Calendar', style: TextStyle(color: Colors.white)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onPressed: () => context.go('/calendar'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeadlinesSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Task>> tasksAsync,
  ) {
    final settings = ref.watch(settingsNotifierProvider);
    final now = TimezoneService.instance.activeNow(settings);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Uncompleted Tasks & Deadlines',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 20),
              onPressed: () => AddTaskDialog.show(context),
            ),
          ],
        ),
        const SizedBox(height: 8),
        tasksAsync.when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
          error: (err, _) => Text('Error loading tasks: $err'),
          data: (tasks) {
            if (tasks.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.done_all, color: Colors.green),
                      SizedBox(width: 12),
                      Text('No outstanding deadlines! You\'re up to date.'),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: tasks.take(5).map((task) {
                final due = TimezoneService.instance.toActiveTime(task.dueDate, settings);
                final isOverdue = due.isBefore(now);
                final hoursUntil = due.difference(now).inHours;
                final isUrgent = hoursUntil <= 24;
                final isWarning = hoursUntil <= 72;

                Color badgeColor = Colors.grey;
                String statusText = DateFormat('MMM d, HH:mm').format(due);

                if (isOverdue) {
                  badgeColor = Colors.red;
                  statusText = 'OVERDUE';
                } else if (isUrgent) {
                  badgeColor = Colors.deepOrange;
                  statusText = 'Due in ${hoursUntil}h';
                } else if (isWarning) {
                  badgeColor = Colors.amber.shade800;
                  statusText = 'Due in ${(hoursUntil / 24).ceil()} days';
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Checkbox(
                      value: task.isCompleted,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      onChanged: (val) async {
                        await ref.read(taskRepositoryProvider).completeTask(task.id);
                        ref.invalidate(dashboardTasksProvider);
                        ref.invalidate(incompleteTasksStreamProvider);
                      },
                    ),
                    title: Text(
                      task.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        CategoryBadge(categorySlugOrName: task.category, compact: true),
                        const SizedBox(width: 8),
                        if (task.isRecurring)
                          const Row(
                            children: [
                              Icon(Icons.repeat, size: 12, color: Colors.grey),
                              SizedBox(width: 2),
                              Text('Weekly', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                      ],
                    ),
                    onTap: () => EditTaskDialog.show(context, task),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              color: badgeColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.blueGrey),
                          tooltip: 'Edit Task',
                          onPressed: () => EditTaskDialog.show(context, task),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildTodayTimeline(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Event>> eventsAsync,
    List<Category> categories,
  ) {
    final settings = ref.watch(settingsNotifierProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Today\'s Timeline',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 20),
              onPressed: () => AddEventDialog.show(context),
            ),
          ],
        ),
        const SizedBox(height: 8),
        eventsAsync.when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
          error: (err, _) => Text('Error loading events: $err'),
          data: (events) {
            if (events.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.calendar_month, color: Colors.grey, size: 36),
                        SizedBox(height: 8),
                        Text(
                          'No scheduled events today.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Tap + to add a class, commute, gym, or meeting.',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final sortedEvents = List<Event>.from(events)
              ..sort((a, b) {
                // Hard events (!isAutoScheduled) first, soft (isAutoScheduled) later
                if (!a.isAutoScheduled && b.isAutoScheduled) return -1;
                if (a.isAutoScheduled && !b.isAutoScheduled) return 1;
                return a.startTime.compareTo(b.startTime);
              });

            return Column(
              children: sortedEvents.map((event) {
                final isCommute = event.eventType == 'commute';
                final isReminder = event.eventType == 'reminder';
                final isAutoPrep = event.isAutoScheduled;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isReminder
                          ? Colors.amber.withValues(alpha: 0.15)
                          : _getCategoryColor(event.category).withValues(alpha: 0.15),
                      child: isReminder
                          ? const Icon(Icons.notifications_active, color: Colors.amber, size: 20)
                          : Text(
                              _getCategoryEmoji(event.category, categories),
                              style: const TextStyle(fontSize: 18),
                            ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (isReminder)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Reminder',
                              style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold),
                            ),
                          )
                        else if (isAutoPrep)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Scheduled',
                              style: TextStyle(fontSize: 10, color: Colors.purple, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              isReminder
                                  ? 'Reminder at ${DateFormat('HH:mm').format(TimezoneService.instance.toActiveTime(event.startTime, settings))}'
                                  : '${DateFormat('HH:mm').format(TimezoneService.instance.toActiveTime(event.startTime, settings))} – ${DateFormat('HH:mm').format(TimezoneService.instance.toActiveTime(event.endTime, settings))}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(width: 8),
                            CategoryBadge(categorySlugOrName: event.category, compact: true),
                          ],
                        ),
                        if (isCommute && event.notes != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: Text(
                              '💡 Commute mode: ${event.notes}',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.timer_outlined, size: 20),
                          tooltip: 'Focus on this event',
                          onPressed: () {
                            FocusTimerDialog.show(
                              context,
                              title: event.title,
                              category: event.category,
                              defaultMinutes: 30,
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.blueGrey),
                          tooltip: 'Edit Event',
                          onPressed: () => EditEventDialog.show(context, event),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHabitsSection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Habit>> habitsAsync,
    AsyncValue<Map<int, int>> countsAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Habits This Week',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              'Frequency cadence',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        habitsAsync.when(
          loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
          error: (err, _) => Text('Error loading habits: $err'),
          data: (habits) {
            final counts = countsAsync.value ?? {};

            if (habits.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(Icons.repeat, color: Colors.grey),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text('No habits created yet (e.g. personal research, instrument practice).'),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Column(
              children: habits.map((habit) {
                final completed = counts[habit.id] ?? 0;
                final target = habit.targetFrequencyPerWeek;
                final progress = target > 0 ? (completed / target).clamp(0.0, 1.0) : 0.0;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CategoryBadge(categorySlugOrName: habit.category, compact: true),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                habit.title,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                            ),
                            Text(
                              target == 7
                                  ? '🔥 Daily • $completed / 7'
                                  : '$completed / $target this week',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: completed >= target ? Colors.green : (target == 7 ? Colors.purple : Colors.blueGrey),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: Colors.blueGrey, size: 20),
                              tooltip: 'Edit Habit',
                              onPressed: () => EditHabitDialog.show(context, habit),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle, color: Colors.green, size: 24),
                              tooltip: 'Log completed session',
                              onPressed: () => LogHabitDialog.show(context, habit),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              completed >= target ? Colors.green : Colors.blueAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }


  String _getCategoryEmoji(String categorySlugOrName, List<Category> categories) {
    for (final c in categories) {
      if (c.slug.toLowerCase() == categorySlugOrName.toLowerCase() ||
          c.name.toLowerCase() == categorySlugOrName.toLowerCase()) {
        if (c.emoji.isNotEmpty) return c.emoji;
      }
    }
    return switch (categorySlugOrName.toLowerCase()) {
      'schoolwork' => '🎓',
      'work' => '💼',
      'research' => '🔬',
      'personal' => '🧘',
      'social' => '🎉',
      'commute' || 'transportation' => '🚆',
      _ => '🌐',
    };
  }

  Color _getCategoryColor(String category) {
    return switch (category.toLowerCase()) {
      'schoolwork' => const Color(0xFF4A90D9),
      'work' => const Color(0xFFE67E22),
      'research' => const Color(0xFF8E44AD),
      'personal' => const Color(0xFF27AE60),
      'social' => const Color(0xFFEC4899),
      'commute' || 'transportation' => const Color(0xFFE74C3C),
      _ => const Color(0xFF3B82F6),
    };
  }
}

