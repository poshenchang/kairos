// lib/ui/widgets/edit_task_dialog.dart
//
// Modal dialog to edit an existing task and manage its subtasks.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/timezone_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';

class EditTaskDialog extends ConsumerStatefulWidget {
  final Task task;

  const EditTaskDialog({super.key, required this.task});

  static Future<void> show(BuildContext context, Task task) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => EditTaskDialog(task: task),
    );
  }

  @override
  ConsumerState<EditTaskDialog> createState() => _EditTaskDialogState();
}

class _EditTaskDialogState extends ConsumerState<EditTaskDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  final TextEditingController _subtaskInputController = TextEditingController();

  late String _selectedCategory;
  late int _selectedPriority;
  late DateTime _dueDate;
  late TimeOfDay _dueTime;
  late int _estimatedMinutes;
  late bool _isRecurring;
  String _repeatEndMode = 'indefinite';
  DateTime? _repeatUntilDate;
  int _repeatCount = 10;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleController = TextEditingController(text: t.title);
    _descController = TextEditingController(text: t.description ?? '');

    final settings = ref.read(settingsNotifierProvider);
    final activeDue = TimezoneService.instance.toActiveTime(t.dueDate, settings);
    _dueDate = DateTime(activeDue.year, activeDue.month, activeDue.day);
    _dueTime = TimeOfDay(hour: activeDue.hour, minute: activeDue.minute);

    _selectedCategory = t.category;
    _selectedPriority = t.priority;
    _estimatedMinutes = t.estimatedMinutes ?? 120;
    _isRecurring = t.isRecurring;

    if (t.rrule != null) {
      if (t.rrule!.contains('UNTIL=')) {
        _repeatEndMode = 'until_date';
        final match = RegExp(r'UNTIL=(\d{8})').firstMatch(t.rrule!);
        if (match != null) {
          final s = match.group(1)!;
          _repeatUntilDate = DateTime(
            int.parse(s.substring(0, 4)),
            int.parse(s.substring(4, 6)),
            int.parse(s.substring(6, 8)),
          );
        }
      } else if (t.rrule!.contains('COUNT=')) {
        _repeatEndMode = 'count';
        final match = RegExp(r'COUNT=(\d+)').firstMatch(t.rrule!);
        if (match != null) {
          _repeatCount = int.tryParse(match.group(1)!) ?? 10;
        }
      }
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
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _subtaskInputController.dispose();
    super.dispose();
  }

  Future<void> _updateTask() async {
    if (!_formKey.currentState!.validate()) return;

    final activeDue = DateTime(
      _dueDate.year,
      _dueDate.month,
      _dueDate.day,
      _dueTime.hour,
      _dueTime.minute,
    );

    final settings = ref.read(settingsNotifierProvider);
    final dueDateTime = TimezoneService.instance.fromActiveTime(activeDue, settings);

    String? rrule;
    if (_isRecurring) {
      final baseRule = 'FREQ=WEEKLY;BYDAY=${_dayToRruleCode(_dueDate.weekday)}';
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
    final updatedCompanion = widget.task.toCompanion(true).copyWith(
      title: Value(_titleController.text.trim()),
      category: Value(_selectedCategory),
      priority: Value(_selectedPriority),
      description: _descController.text.isNotEmpty
          ? Value(_descController.text.trim())
          : const Value(null),
      dueDate: Value(dueDateTime),
      estimatedMinutes: Value(_estimatedMinutes),
      isRecurring: Value(_isRecurring),
      rrule: Value(rrule),
      updatedAt: Value(DateTime.now().toUtc()),
    );

    await taskDao.updateTask(updatedCompanion);

    ref.invalidate(dashboardTasksProvider);
    ref.invalidate(incompleteTasksStreamProvider);

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(allCategoriesProvider);
    final categories = categoriesAsync.value ?? [];
    final taskDao = ref.watch(taskDaoProvider);

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
                    'Edit Task & Subtasks',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Task Title',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.check_circle_outline),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: 'Description / Instructions (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.notes),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
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
                      initialValue: _selectedPriority,
                      decoration: const InputDecoration(
                        labelText: 'Priority',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('🟢 Low')),
                        DropdownMenuItem(value: 3, child: Text('🟡 Medium')),
                        DropdownMenuItem(value: 5, child: Text('🔴 High')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedPriority = val);
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
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(DateFormat('MMM d, yyyy').format(_dueDate)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _dueDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                        );
                        if (picked != null) setState(() => _dueDate = picked);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Text(_dueTime.format(context)),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _dueTime,
                        );
                        if (picked != null) setState(() => _dueTime = picked);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
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
                value: _estimatedMinutes.toDouble().clamp(15.0, 360.0),
                min: 15,
                max: 360,
                divisions: 23,
                label: _formatDuration(_estimatedMinutes),
                onChanged: (val) => setState(() => _estimatedMinutes = val.toInt()),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Repeating Weekly Task'),
                subtitle: const Text('Automatically rolls deadline forward upon completion'),
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
                              initialDate: _repeatUntilDate ?? _dueDate.add(const Duration(days: 90)),
                              firstDate: _dueDate,
                              lastDate: _dueDate.add(const Duration(days: 730)),
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
              const Divider(height: 24),
              // Subtasks Section
              const Text('Subtasks / Milestones', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              StreamBuilder<List<Subtask>>(
                stream: taskDao.watchSubtasksForTask(widget.task.id),
                builder: (context, snapshot) {
                  final subtasks = snapshot.data ?? [];
                  return Column(
                    children: [
                      ...subtasks.map((s) => ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Checkbox(
                          value: s.isCompleted,
                          onChanged: (val) async {
                            await taskDao.toggleSubtask(s.id, val ?? false);
                          },
                        ),
                        title: Text(
                          s.title,
                          style: TextStyle(
                            fontSize: 13,
                            decoration: s.isCompleted ? TextDecoration.lineThrough : null,
                            color: s.isCompleted ? Colors.grey : null,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                          onPressed: () async {
                            await taskDao.deleteSubtask(s.id);
                          },
                        ),
                      )),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _subtaskInputController,
                              decoration: const InputDecoration(
                                hintText: 'Add subtask (e.g. read chapter 2)...',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              onSubmitted: (val) async {
                                if (val.trim().isNotEmpty) {
                                  await taskDao.insertSubtask(SubtasksCompanion.insert(
                                    taskId: widget.task.id,
                                    title: val.trim(),
                                  ));
                                  _subtaskInputController.clear();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            child: const Text('Add'),
                            onPressed: () async {
                              final text = _subtaskInputController.text.trim();
                              if (text.isNotEmpty) {
                                await taskDao.insertSubtask(SubtasksCompanion.insert(
                                  taskId: widget.task.id,
                                  title: text,
                                ));
                                _subtaskInputController.clear();
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _updateTask,
                  icon: const Icon(Icons.check),
                  label: const Text('Save Task Changes', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
