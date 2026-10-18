// lib/ui/screens/dashboard/dashboard_screen.dart
//
// Main Dashboard: Hero Suggestion, Deadlines, Today's Timeline, Habits.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/core/scheduler/scheduler_provider.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/widgets/add_event_dialog.dart';
import 'package:kairos/ui/widgets/add_task_dialog.dart';
import 'package:kairos/ui/widgets/category_badge.dart';
import 'package:kairos/ui/widgets/focus_timer_dialog.dart';
import 'package:kairos/ui/widgets/help_guide_dialog.dart';
import 'package:kairos/ui/widgets/log_habit_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:kairos/ui/widgets/app_global_actions.dart';
import 'package:kairos/ui/theme/theme_provider.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final suggestion = ref.watch(smartSuggestionProvider);
    final todayEventsAsync = ref.watch(todayEventsProvider);
    final dashboardTasksAsync = ref.watch(dashboardTasksProvider);
    final activeHabitsAsync = ref.watch(activeHabitsProvider);
    final habitCountsAsync = ref.watch(weeklyHabitCompletionsProvider);
    final schedulerState = ref.watch(schedulerNotifierProvider);

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
          ref.invalidate(todayEventsProvider);
          ref.invalidate(dashboardTasksProvider);
          ref.invalidate(activeHabitsProvider);
          ref.invalidate(weeklyHabitCompletionsProvider);
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
              _buildTodayTimeline(context, ref, todayEventsAsync),

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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF4F46E5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withOpacity(0.3),
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
              const Icon(Icons.lightbulb_outline, color: Colors.amberAccent, size: 20),
              const SizedBox(width: 8),
              const Text(
                'WHAT TO DO NEXT',
                style: TextStyle(
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
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(suggestion.actionLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF2563EB),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () {
                  FocusTimerDialog.show(
                    context,
                    title: suggestion.title,
                    category: suggestion.category,
                    defaultMinutes: 25,
                  );
                },
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.sync, color: Colors.white, size: 16),
                label: const Text('Reschedule', style: TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onPressed: () => ref.read(schedulerNotifierProvider.notifier).run(),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Uncompleted Tasks & Deadlines',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.done_all, color: Colors.green),
                      const SizedBox(width: 12),
                      const Text('No outstanding deadlines! You\'re up to date.'),
                    ],
                  ),
                ),
              );
            }

            final now = DateTime.now();

            return Column(
              children: tasks.take(5).map((task) {
                final isOverdue = task.dueDate.isBefore(now);
                final hoursUntil = task.dueDate.difference(now).inHours;
                final isUrgent = hoursUntil <= 24;
                final isWarning = hoursUntil <= 72;

                Color badgeColor = Colors.grey;
                String statusText = DateFormat('MMM d, HH:mm').format(task.dueDate);

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
                        await ref.read(taskDaoProvider).markCompleted(task.id);
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
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: badgeColor.withOpacity(0.12),
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
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Today\'s Timeline',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Center(
                    child: Column(
                      children: [
                        const Icon(Icons.calendar_month, color: Colors.grey, size: 36),
                        const SizedBox(height: 8),
                        const Text(
                          'No scheduled events today.',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const Text(
                          'Tap + to add a class, commute, gym, or meeting.',
                          style: TextStyle(fontSize: 13, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Column(
              children: events.map((event) {
                final isCommute = event.eventType == 'commute';
                final isAutoPrep = event.isAutoScheduled;

                IconData eventIcon = Icons.event;
                if (isCommute) eventIcon = Icons.train;
                else if (event.eventType == 'gym') eventIcon = Icons.fitness_center;
                else if (event.eventType == 'interview') eventIcon = Icons.work_outline;
                else if (event.eventType == 'lecture') eventIcon = Icons.school_outlined;
                else if (isAutoPrep) eventIcon = Icons.auto_awesome;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isAutoPrep
                          ? Colors.purple.shade50
                          : isCommute
                              ? Colors.red.shade50
                              : Colors.blue.shade50,
                      child: Icon(
                        eventIcon,
                        color: isAutoPrep
                            ? Colors.purple
                            : isCommute
                                ? Colors.red
                                : Colors.blueAccent,
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
                        if (isAutoPrep)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Auto-Prep',
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
                              '${DateFormat('HH:mm').format(event.startTime)} – ${DateFormat('HH:mm').format(event.endTime)}',
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
                    trailing: IconButton(
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
            const Text(
              'Habits This Week',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      const Icon(Icons.repeat, color: Colors.grey),
                      const SizedBox(width: 12),
                      const Expanded(
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
                              '$completed / $target this week',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: completed >= target ? Colors.green : Colors.blueGrey,
                              ),
                            ),
                            const SizedBox(width: 8),
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
}

