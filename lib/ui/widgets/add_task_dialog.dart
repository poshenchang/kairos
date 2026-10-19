// lib/ui/widgets/add_task_dialog.dart
//
// Modal dialog to create a deadline-based task (one-off or weekly recurring).

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/form_defaults_service.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/timezone_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';

class AddTaskDialog extends ConsumerStatefulWidget {
  const AddTaskDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const AddTaskDialog(),
    );
  }

  @override
  ConsumerState<AddTaskDialog> createState() => _AddTaskDialogState();
}

class _AddTaskDialogState extends ConsumerState<AddTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _subtaskInputController = TextEditingController();

  final List<String> _pendingSubtasks = [];

  DateTime _selectedDate = DateTime.now().add(const Duration(days: 2));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 23, minute: 59);

  String _selectedCategory = 'schoolwork';
  int _priority = 3; // 1=Low, 3=Medium, 5=High
  bool _isRecurring = false;
  String _repeatEndMode = 'indefinite'; // 'indefinite', 'until_date', 'count'
  DateTime? _repeatUntilDate;
  int _repeatCount = 10;
  int _estimatedMinutes = 120; // Default 2 hours suggested session duration

  @override
  void initState() {
    super.initState();
    final defaults = ref.read(formDefaultsServiceProvider);
    _selectedDate = defaults.lastTaskDueDate ?? DateTime.now().add(const Duration(days: 2));
    _selectedTime = defaults.lastTaskDueTime ?? const TimeOfDay(hour: 23, minute: 59);
    _selectedCategory = defaults.lastTaskCategory ?? 'schoolwork';
    _estimatedMinutes = defaults.lastTaskEstimatedMinutes ?? 120;
    _repeatUntilDate = _selectedDate.add(const Duration(days: 90));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _subtaskInputController.dispose();
    super.dispose();
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;

    final activeDue = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );

    final settings = ref.read(settingsNotifierProvider);
    final dueDateTime = TimezoneService.instance.fromActiveTime(activeDue, settings);

    String? rrule;
    if (_isRecurring) {
      final baseRule = 'FREQ=WEEKLY;BYDAY=${_dayToRruleCode(_selectedDate.weekday)}';
      if (_repeatEndMode == 'until_date' && _repeatUntilDate != null) {
        final u = _repeatUntilDate!;
        final uStr = '${u.year}${u.month.toString().padLeft(2, '0')}${u.day.toString().padLeft(2, '0')}T235959Z';
        rrule = '$baseRule;UNTIL=$uStr';
      } else if (_repeatEndMode == 'count') {
        rrule = '$baseRule;COUNT=$_repeatCount';
      } else {
        rrule = baseRule;
      }
    }

    final taskDao = ref.read(taskDaoProvider);
    final taskId = await taskDao.insertTask(
      TasksCompanion.insert(
        title: _titleController.text.trim(),
        category: Value(_selectedCategory),
        dueDate: dueDateTime,
        description: _descController.text.isNotEmpty
            ? Value(_descController.text.trim())
            : const Value(null),
        priority: Value(_priority),
        isRecurring: Value(_isRecurring),
        rrule: Value(rrule),
        estimatedMinutes: Value(_estimatedMinutes),
      ),
    );

    for (final st in _pendingSubtasks) {
      if (st.trim().isNotEmpty) {
        await taskDao.insertSubtask(
          SubtasksCompanion.insert(
            taskId: taskId,
            title: st.trim(),
          ),
        );
      }
    }

    await ref.read(formDefaultsServiceProvider).saveTaskDefaults(
      dueDate: _selectedDate,
      dueTime: _selectedTime,
      estimatedMinutes: _estimatedMinutes,
      category: _selectedCategory,
    );

    if (mounted) Navigator.of(context).pop();
  }

  void _addPendingSubtask() {
    final text = _subtaskInputController.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _pendingSubtasks.add(text);
        _subtaskInputController.clear();
      });
    }
  }

  String _dayToRruleCode(int weekday) {
    const map = {1: 'MO', 2: 'TU', 3: 'WE', 4: 'TH', 5: 'FR', 6: 'SA', 7: 'SU'};
    return map[weekday] ?? 'MO';
  }

  String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(allCategoriesProvider);
    final categories = categoriesAsync.value ?? [];

    return Padding(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'New Deadline / Task',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Task or Deadline Title',
                  hintText: 'e.g. OS Project Submission, Essay Draft, Job Application',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              // Category & Priority
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedCategory,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        border: OutlineInputBorder(),
                      ),
                      items: categories.map((cat) {
                        return DropdownMenuItem(
                          value: cat.slug,
                          child: Text('${cat.emoji} ${cat.name}'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedCategory = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _priority,
                      decoration: const InputDecoration(
                        labelText: 'Priority',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('🟢 Low')),
                        DropdownMenuItem(value: 3, child: Text('🟡 Medium')),
                        DropdownMenuItem(value: 5, child: Text('🔴 High / Urgent')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _priority = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Due Date & Time
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today),
                      label: Text(DateFormat('MMM d, yyyy').format(_selectedDate)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 7)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setState(() => _selectedDate = picked);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time),
                      label: Text(_selectedTime.format(context)),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _selectedTime,
                        );
                        if (picked != null) setState(() => _selectedTime = picked);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Weekly Recurring Deadline'),
                subtitle: const Text('e.g. Weekly problem set. Dashboard shows only next instance.'),
                value: _isRecurring,
                onChanged: (val) => setState(() => _isRecurring = val),
              ),
              if (_isRecurring) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, bottom: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Repeat ends:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'indefinite', label: Text('Never')),
                          ButtonSegment(value: 'until_date', label: Text('Until Date')),
                          ButtonSegment(value: 'count', label: Text('N Weeks')),
                        ],
                        selected: {_repeatEndMode},
                        onSelectionChanged: (s) => setState(() => _repeatEndMode = s.first),
                      ),
                      if (_repeatEndMode == 'until_date') ...[
                        const SizedBox(height: 6),
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.event_busy, size: 20),
                          title: Text(
                            _repeatUntilDate != null
                                ? 'Repeats until: ${DateFormat('MMM d, yyyy').format(_repeatUntilDate!)}'
                                : 'Choose termination date',
                            style: const TextStyle(fontSize: 13),
                          ),
                          trailing: const Icon(Icons.calendar_month, size: 20),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _repeatUntilDate ?? _selectedDate.add(const Duration(days: 90)),
                              firstDate: _selectedDate,
                              lastDate: _selectedDate.add(const Duration(days: 730)),
                            );
                            if (picked != null) setState(() => _repeatUntilDate = picked);
                          },
                        ),
                      ],
                      if (_repeatEndMode == 'count') ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Text('Repeat for:', style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 12),
                            DropdownButton<int>(
                              value: [2, 3, 4, 5, 6, 8, 10, 12, 14, 16, 20, 26, 52].contains(_repeatCount) ? _repeatCount : 10,
                              items: [2, 3, 4, 5, 6, 8, 10, 12, 14, 16, 20, 26, 52].map((cnt) {
                                return DropdownMenuItem(value: cnt, child: Text('$cnt weeks'));
                              }).toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => _repeatCount = v);
                              },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Suggested session duration / time spent:'),
                  Text(
                    _formatDuration(_estimatedMinutes),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Slider(
                value: _estimatedMinutes.toDouble(),
                min: 15,
                max: 360,
                divisions: 23,
                label: _formatDuration(_estimatedMinutes),
                onChanged: (val) => setState(() => _estimatedMinutes = val.toInt()),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: 'Description / Checklist Notes (Optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 14),

              // Subtasks Section
              const Text(
                'Subtasks / Steps (Optional)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              if (_pendingSubtasks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Column(
                    children: _pendingSubtasks.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final sub = entry.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                        child: Row(
                          children: [
                            const Icon(Icons.check_box_outline_blank, size: 16, color: Colors.grey),
                            const SizedBox(width: 8),
                            Expanded(child: Text(sub, style: const TextStyle(fontSize: 13))),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                setState(() => _pendingSubtasks.removeAt(idx));
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _subtaskInputController,
                      decoration: const InputDecoration(
                        hintText: 'Add subtask (e.g. outline draft, write code)...',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontSize: 13),
                      onSubmitted: (_) => _addPendingSubtask(),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    icon: const Icon(Icons.add, size: 18),
                    onPressed: _addPendingSubtask,
                    tooltip: 'Add subtask',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saveTask,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save Deadline / Task', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

