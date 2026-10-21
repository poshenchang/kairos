// lib/ui/screens/habits/habits_screen.dart
//
// Habits screen: frequency-based activities without hard time limits
// (e.g. Personal research, Instrument practice).

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/services/habit_schedule_service.dart';
import 'package:kairos/ui/widgets/add_habit_dialog.dart';
import 'package:kairos/ui/widgets/edit_habit_dialog.dart';
import 'package:kairos/ui/widgets/app_global_actions.dart';
import 'package:kairos/ui/widgets/category_badge.dart';
import 'package:kairos/ui/widgets/habit_schedule_dialog.dart';
import 'package:kairos/ui/widgets/log_habit_dialog.dart';

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(allHabitsProvider);
    final countsAsync = ref.watch(weeklyHabitCompletionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Habits & Frequency', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: const [
          AppGlobalActions(showAddButtons: false),
        ],
      ),
      body: habitsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (habits) {
          final counts = countsAsync.value ?? {};

          if (habits.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.music_note_outlined, size: 54, color: Colors.purple),
                  const SizedBox(height: 12),
                  const Text(
                    'No frequency habits tracked yet!',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32.0),
                    child: Text(
                      'Perfect for daily routines like language learning and podcasts, or regular cadence activities like research and music practice.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => AddHabitDialog.show(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add First Habit'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            // Extra bottom padding so the FAB never covers the last card
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
            itemCount: habits.length,
            itemBuilder: (context, index) {
              final habit = habits[index];
              return _HabitCard(habit: habit, completed: counts[habit.id] ?? 0);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AddHabitDialog.show(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Habit'),
      ),
    );
  }
}


enum _HabitAction { toggleActive, schedule, edit, delete }

class _HabitCard extends ConsumerWidget {
  final Habit habit;
  final int completed;

  const _HabitCard({required this.habit, required this.completed});

  /// "20 min" when min == max, otherwise "120–180 min"; window/day filters appended only when set.
  String get _sessionLabel {
    final parts = <String>[
      habit.minSessionMinutes == habit.maxSessionMinutes
          ? '${habit.minSessionMinutes} min'
          : '${habit.minSessionMinutes}–${habit.maxSessionMinutes} min',
      if (habit.preferredWindow != 'any') habit.preferredWindow,
      if (habit.daysFilter == 'weekdays') '📅 Weekdays only',
      if (habit.daysFilter == 'weekends') '🏖️ Weekends only',
    ];
    return parts.join(' • ');
  }

  Future<void> _toggleActive(WidgetRef ref) async {
    final updatedCompanion = habit.toCompanion(true).copyWith(
          isActive: Value(!habit.isActive),
          updatedAt: Value(DateTime.now().toUtc()),
        );
    await ref.read(habitDaoProvider).updateHabit(updatedCompanion);
    ref.invalidate(allHabitsProvider);
    ref.invalidate(activeHabitsProvider);
  }

  Future<void> _delete(WidgetRef ref) async {
    await ref.read(habitDaoProvider).deleteHabit(habit.id);
    ref.invalidate(allHabitsProvider);
    ref.invalidate(activeHabitsProvider);
    ref.invalidate(weeklyHabitCompletionsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final target = habit.targetFrequencyPerWeek;
    final progress = target > 0 ? (completed / target).clamp(0.0, 1.0) : 0.0;
    final isDoneForWeek = completed >= target;
    final progressColor = isDoneForWeek ? Colors.green : (target == 7 ? Colors.purpleAccent : Colors.blueAccent);
    final defaultSlots = ref.watch(habitScheduleProvider)[habit.id] ?? [];

    final logButton = ElevatedButton.icon(
      icon: const Icon(Icons.check, size: 16),
      label: const Text('Log Session', style: TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      onPressed: () => LogHabitDialog.show(context, habit),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: !habit.isActive
              ? Colors.amber.shade200
              : (isDoneForWeek
                  ? Colors.green.shade200
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
          width: (!habit.isActive || isDoneForWeek) ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row: title gets all remaining width, actions sit at the end
            Row(
              children: [
                Expanded(
                  child: Text(
                    habit.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                if (isMobile)
                  PopupMenuButton<_HabitAction>(
                    icon: const Icon(Icons.more_vert, color: Colors.grey),
                    tooltip: 'More actions',
                    onSelected: (action) {
                      switch (action) {
                        case _HabitAction.toggleActive:
                          _toggleActive(ref);
                        case _HabitAction.schedule:
                          HabitScheduleDialog.show(context, habit);
                        case _HabitAction.edit:
                          EditHabitDialog.show(context, habit);
                        case _HabitAction.delete:
                          _delete(ref);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _HabitAction.toggleActive,
                        child: ListTile(
                          leading: Icon(habit.isActive ? Icons.pause_circle_outline : Icons.play_circle_outline),
                          title: Text(habit.isActive ? 'Pause in Assistant' : 'Resume in Assistant'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: _HabitAction.schedule,
                        child: ListTile(
                          leading: Icon(Icons.settings_suggest_outlined),
                          title: Text('Default Weekly Schedule'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: _HabitAction.edit,
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: _HabitAction.delete,
                        child: ListTile(
                          leading: Icon(Icons.delete_outline, color: Colors.red),
                          title: Text('Delete', style: TextStyle(color: Colors.red)),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  )
                else ...[
                  IconButton(
                    icon: Icon(
                      habit.isActive ? Icons.toggle_on : Icons.toggle_off_outlined,
                      size: 26,
                      color: habit.isActive ? Colors.green : Colors.grey,
                    ),
                    tooltip: habit.isActive ? 'Active in Assistant (Click to pause)' : 'Paused in Assistant (Click to activate)',
                    onPressed: () => _toggleActive(ref),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_suggest_outlined, size: 20, color: Colors.purpleAccent),
                    tooltip: 'Default Weekly Schedule',
                    onPressed: () => HabitScheduleDialog.show(context, habit),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blueGrey),
                    tooltip: 'Edit Habit',
                    onPressed: () => EditHabitDialog.show(context, habit),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                    tooltip: 'Delete Habit',
                    onPressed: () => _delete(ref),
                  ),
                ],
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      CategoryBadge(categorySlugOrName: habit.category),
                      if (!habit.isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber.shade400),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.pause_circle_outline, size: 14, color: Colors.amber.shade800),
                              const SizedBox(width: 4),
                              Text(
                                'Paused',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (defaultSlots.isNotEmpty)
                        InkWell(
                          onTap: () => HabitScheduleDialog.show(context, habit),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              '🗓️ ${defaultSlots.length} default slots',
                              style: const TextStyle(fontSize: 10.5, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (habit.description != null && habit.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        habit.description!,
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                    ),
                  const SizedBox(height: 14),
                  // Progress bar with its weekly count alongside
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 8,
                            backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        target == 7 ? '🔥 $completed / 7 this week' : '$completed / $target this week',
                        style: TextStyle(color: progressColor, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _sessionLabel,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Phones: full-width button; wider screens: right-aligned
                  if (isMobile)
                    SizedBox(width: double.infinity, child: logButton)
                  else
                    Align(alignment: Alignment.centerRight, child: logButton),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
