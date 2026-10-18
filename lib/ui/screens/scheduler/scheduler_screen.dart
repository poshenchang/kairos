// lib/ui/screens/scheduler/scheduler_screen.dart
//
// Auto-Scheduler controls, warnings, preferences, and custom category manager.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/core/scheduler/scheduler_provider.dart';
import 'package:kairos/core/scheduler/scheduler_types.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/theme/app_theme.dart';
import 'package:kairos/ui/widgets/app_global_actions.dart';
import 'package:kairos/ui/widgets/help_guide_dialog.dart';

class SchedulerScreen extends ConsumerWidget {
  const SchedulerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulerState = ref.watch(schedulerNotifierProvider);
    final categoriesAsync = ref.watch(allCategoriesProvider);
    final categories = categoriesAsync.value ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto-Scheduler', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: const [
          AppGlobalActions(showScheduler: false),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. AUTO-SCHEDULER STATUS CARD
            _buildSchedulerHero(context, ref, schedulerState),

            const SizedBox(height: 24),

            // 2. WARNINGS & ALERTS (If any from last run)
            if (schedulerState.value != null && schedulerState.value!.warnings.isNotEmpty)
              _buildWarningsCard(schedulerState.value!.warnings),

            const SizedBox(height: 24),

            // 3. AUTO-SCHEDULED BLOCKS SUMMARY
            _buildUpcomingAutoBlocks(context, ref),

            const SizedBox(height: 24),

            // 4. CATEGORY MANAGER
            _buildCategoryManager(context, ref, categories),

            const SizedBox(height: 24),

            // 5. COMMUTE & STUDENT PRODUCTIVITY TIPS
            _buildStudentTipsCard(context),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSchedulerHero(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<ScheduleResult?> state,
  ) {
    final isLoading = state.isLoading;
    final lastResult = state.value;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.blueAccent, size: 28),
                SizedBox(width: 12),
                Text(
                  'Kairos Smart Scheduler',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'The auto-scheduler analyzes your fixed classes, meetings, and transit slots, then finds optimal free gaps to schedule exam preparation blocks and weekly habit sessions (piano, violin, research).',
              style: TextStyle(fontSize: 13, height: 1.45, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (lastResult != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: Colors.blueAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Last run: Scheduled ${lastResult.events.length} blocks with ${lastResult.warnings.length} warnings.',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton.icon(
                icon: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(isLoading ? 'Optimizing Schedule...' : 'Run Auto-Scheduler Now'),
                onPressed: isLoading
                    ? null
                    : () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Auto-scheduler running... finding free slots!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                        await ref.read(schedulerNotifierProvider.notifier).run();
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningsCard(List<SchedulerWarning> warnings) {
    return Card(
      color: Colors.orange.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                SizedBox(width: 8),
                Text(
                  'Schedule Alerts',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orangeAccent),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...warnings.map(
              (w) => Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
                    Expanded(child: Text(w.message, style: const TextStyle(fontSize: 13, height: 1.35))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingAutoBlocks(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final todayAsync = ref.watch(todayEventsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.calendar_view_week, color: Colors.purpleAccent),
                SizedBox(width: 8),
                Text(
                  'Today\'s Auto-Scheduled Blocks',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            todayAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (events) {
                final autoBlocks = events.where((e) => e.isAutoScheduled).toList();
                if (autoBlocks.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'No auto-scheduled blocks today. Hit "Run Auto-Scheduler Now" above to generate study and habit sessions.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  );
                }

                return Column(
                  children: autoBlocks.map((block) {
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.purpleAccent,
                        child: Icon(Icons.flash_on, size: 16, color: Colors.white),
                      ),
                      title: Text(block.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${DateFormat('h:mm a').format(block.startTime.toLocal())} – ${DateFormat('h:mm a').format(block.endTime.toLocal())}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () async {
                          await ref.read(eventDaoProvider).deleteEvent(block.id);
                          ref.invalidate(todayEventsProvider);
                        },
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryManager(
    BuildContext context,
    WidgetRef ref,
    List<Category> categories,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.category_outlined, color: Colors.teal),
                const SizedBox(width: 8),
                const Text(
                  'Categories & Tags',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Category'),
                  onPressed: () => _showAddCategoryDialog(context, ref),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: categories.map((c) {
                final color = AppTheme.colorFromHex(c.colorHex);
                return Chip(
                  avatar: Text(c.emoji),
                  label: Text(c.name),
                  backgroundColor: color.withOpacity(0.12),
                  side: BorderSide(color: color.withOpacity(0.4)),
                  labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentTipsCard(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.lightbulb_outline, color: Colors.amber),
                SizedBox(width: 8),
                Text(
                  'Student Scheduling Tips',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '• Long Commute? Mark your transit event as "Commute". Kairos will suggest reviewing lecture notes, reading papers, or listening to podcasts during the ride.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '• Need Exam Prep? When creating an exam event, check "Requires Preparation Block" and choose 120-180m. Kairos will scatter study blocks across the preceding days automatically.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCategoryDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    String emoji = '🎯';
    String colorHex = AppTheme.presetColors.first;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('New Category'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Category Name',
                    hintText: 'e.g. Piano, Club, Side Project',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Emoji: '),
                    const SizedBox(width: 8),
                    ...['🎯', '🎨', '🚀', '💻', '📚', '🏃'].map(
                      (e) => InkWell(
                        onTap: () => setState(() => emoji = e),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: emoji == e ? Colors.blue.shade100 : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(e, style: const TextStyle(fontSize: 20)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Color: '),
                    const SizedBox(width: 8),
                    ...AppTheme.presetColors.take(5).map(
                      (hex) => InkWell(
                        onTap: () => setState(() => colorHex = hex),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppTheme.colorFromHex(hex),
                            shape: BoxShape.circle,
                            border: colorHex == hex ? Border.all(color: Colors.black, width: 2) : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  final name = nameCtrl.text.trim();
                  final slug = name.toLowerCase().replaceAll(RegExp(r'\s+'), '_');

                  await ref.read(categoryDaoProvider).insertCategory(
                    CategoriesCompanion.insert(
                      name: name,
                      slug: slug,
                      emoji: Value(emoji),
                      colorHex: Value(colorHex),
                      isSystem: const Value(false),
                    ),
                  );
                  ref.invalidate(allCategoriesProvider);
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }
}
