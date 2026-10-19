// lib/ui/widgets/log_habit_dialog.dart
//
// Dialog to log a completed habit session.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/ui/providers/app_providers.dart';

class LogHabitDialog extends ConsumerStatefulWidget {
  final Habit habit;

  const LogHabitDialog({super.key, required this.habit});

  static Future<void> show(BuildContext context, Habit habit) async {
    // For daily habits, check if already completed today before showing dialog
    if (habit.targetFrequencyPerWeek >= 7) {
      final container = ProviderScope.containerOf(context, listen: false);
      final habitDao = container.read(habitDaoProvider);
      final localNow = DateTime.now();
      final todayStart = DateTime(localNow.year, localNow.month, localNow.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      final logsToday = await habitDao.getLogsForHabit(habit.id, from: todayStart, to: todayEnd);

      if (logsToday.any((l) => !l.isDeleted)) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You\'ve already completed "${habit.title}" today! Daily habits can only be logged once per day.',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.amber.shade900,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }
    }

    if (!context.mounted) return;
    return showDialog(
      context: context,
      builder: (_) => LogHabitDialog(habit: habit),
    );
  }

  @override
  ConsumerState<LogHabitDialog> createState() => _LogHabitDialogState();
}

class _LogHabitDialogState extends ConsumerState<LogHabitDialog> {
  int _durationMinutes = 45;
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _durationMinutes = widget.habit.minSessionMinutes;
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _logSession() async {
    final habitDao = ref.read(habitDaoProvider);
    final localNow = DateTime.now();
    final todayStart = DateTime(localNow.year, localNow.month, localNow.day);
    final todayEnd = todayStart.add(const Duration(days: 1));

    // For daily habits, guard against multiple entries on the same day
    if (widget.habit.targetFrequencyPerWeek >= 7) {
      final logsToday = await habitDao.getLogsForHabit(widget.habit.id, from: todayStart, to: todayEnd);
      if (logsToday.any((l) => !l.isDeleted)) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You\'ve already completed "${widget.habit.title}" today! Daily habits can only be logged once per day.',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.amber.shade900,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }
    }

    final now = DateTime.now().toUtc();
    await habitDao.logHabitCompletion(
      HabitLogsCompanion.insert(
        syncId: Value(const Uuid().v4()),
        habitId: widget.habit.id,
        completedAt: now,
        durationMinutes: Value(_durationMinutes),
        notes: _notesController.text.isNotEmpty
            ? Value(_notesController.text.trim())
            : const Value(null),
        isDeleted: const Value(false),
        updatedAt: Value(now),
      ),
    );

    // Invalidate weekly and today counts so UI updates immediately
    ref.invalidate(weeklyHabitCompletionsProvider);
    ref.invalidate(todayHabitCompletionsProvider);

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Colors.green),
          const SizedBox(width: 8),
          Expanded(child: Text('Log "${widget.habit.title}"')),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Session Duration:'),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () {
                  if (_durationMinutes > 15) {
                    setState(() => _durationMinutes -= 15);
                  }
                },
              ),
              Text(
                '$_durationMinutes minutes',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                onPressed: () {
                  setState(() => _durationMinutes += 15);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Session Notes (Optional)',
              hintText: 'e.g. Practiced Chopin Nocturne Op.9 No.2',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _logSession,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: const Text('Save Log'),
        ),
      ],
    );
  }
}

