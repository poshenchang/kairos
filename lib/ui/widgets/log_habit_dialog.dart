// lib/ui/widgets/log_habit_dialog.dart
//
// Dialog to log a completed habit session.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/ui/providers/app_providers.dart';

class LogHabitDialog extends ConsumerStatefulWidget {
  final Habit habit;

  const LogHabitDialog({super.key, required this.habit});

  static Future<void> show(BuildContext context, Habit habit) {
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
    await habitDao.logHabitCompletion(
      HabitLogsCompanion.insert(
        habitId: widget.habit.id,
        completedAt: DateTime.now().toUtc(),
        durationMinutes: Value(_durationMinutes),
        notes: _notesController.text.isNotEmpty
            ? Value(_notesController.text.trim())
            : const Value(null),
      ),
    );

    // Invalidate weekly counts so UI updates immediately
    ref.invalidate(weeklyHabitCompletionsProvider);

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

