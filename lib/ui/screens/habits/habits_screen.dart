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
import 'package:kairos/ui/widgets/focus_timer_dialog.dart';
import 'package:kairos/ui/widgets/habit_schedule_dialog.dart';
import 'package:kairos/ui/widgets/log_habit_dialog.dart';

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(allHabitsProvider);
    final countsAsync = ref.watch(weeklyHabitCompletionsProvider);
    final habitDao = ref.watch(habitDaoProvider);

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
            padding: const EdgeInsets.all(16),
            itemCount: habits.length,
            itemBuilder: (context, index) {
              final habit = habits[index];
              final completed = counts[habit.id] ?? 0;
              final target = habit.targetFrequencyPerWeek;
              final progress = target > 0 ? (completed / target).clamp(0.0, 1.0) : 0.0;
              final isDoneForWeek = completed >= target;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: !habit.isActive
                        ? Colors.amber.shade200
                        : (isDoneForWeek ? Colors.green.shade200 : const Color(0xFFE2E8F0)),
                    width: (!habit.isActive || isDoneForWeek) ? 1.5 : 1.0,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CategoryBadge(categorySlugOrName: habit.category),
                          if (!habit.isActive) ...[
                            const SizedBox(width: 8),
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
                                    'Paused in Assistant',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDoneForWeek
                                  ? Colors.green.shade50
                                  : (target == 7 ? Colors.purple.shade50 : Colors.blue.shade50),
                              borderRadius: BorderRadius.circular(20),
                              border: target == 7
                                  ? Border.all(color: Colors.purple.shade200, width: 1)
                                  : null,
                            ),
                            child: Text(
                              target == 7
                                  ? '🔥 Daily • $completed / 7 this week'
                                  : '$completed / $target this week',
                              style: TextStyle(
                                color: isDoneForWeek
                                    ? Colors.green.shade800
                                    : (target == 7 ? Colors.purple.shade800 : Colors.blueAccent),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              habit.isActive ? Icons.toggle_on : Icons.toggle_off_outlined,
                              size: 26,
                              color: habit.isActive ? Colors.green : Colors.grey,
                            ),
                            tooltip: habit.isActive ? 'Active in Assistant (Click to pause)' : 'Paused in Assistant (Click to activate)',
                            onPressed: () async {
                              final updatedCompanion = habit.toCompanion(true).copyWith(
                                isActive: Value(!habit.isActive),
                                updatedAt: Value(DateTime.now().toUtc()),
                              );
                              await habitDao.updateHabit(updatedCompanion);
                              ref.invalidate(allHabitsProvider);
                              ref.invalidate(activeHabitsProvider);
                            },
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
                            onPressed: () async {
                              await habitDao.deleteHabit(habit.id);
                              ref.invalidate(allHabitsProvider);
                              ref.invalidate(activeHabitsProvider);
                              ref.invalidate(weeklyHabitCompletionsProvider);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        habit.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      if (habit.description != null && habit.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            habit.description!,
                            style: const TextStyle(fontSize: 13, color: Colors.black54),
                          ),
                        ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 10,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDoneForWeek ? Colors.green : Colors.blueAccent,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            '${habit.minSessionMinutes}–${habit.maxSessionMinutes} min (${habit.preferredWindow})${habit.daysFilter == 'weekdays' ? ' • 📅 Weekdays only' : (habit.daysFilter == 'weekends' ? ' • 🏖️ Weekends only' : '')}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          Consumer(
                            builder: (context, ref, _) {
                              final defaultSlots = ref.watch(habitScheduleProvider)[habit.id] ?? [];
                              if (defaultSlots.isEmpty) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(left: 6.0),
                                child: InkWell(
                                  onTap: () => HabitScheduleDialog.show(context, habit),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: Colors.purple.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      '🗓️ ${defaultSlots.length} default slots',
                                      style: const TextStyle(fontSize: 10.5, color: Colors.purple, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          const Spacer(),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.timer_outlined, size: 16),
                            label: const Text('Focus', style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              FocusTimerDialog.show(
                                context,
                                title: habit.title,
                                category: habit.category,
                                defaultMinutes: habit.minSessionMinutes,
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Log Session', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => LogHabitDialog.show(context, habit),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
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

