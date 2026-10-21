// lib/ui/widgets/task_form_sheet.dart
//
// Bottom sheet to create a task or edit an existing one (one-off or weekly
// recurring), including its subtasks. Nothing is written until Save, so
// closing the sheet discards all changes, subtasks included.

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

class TaskFormSheet extends ConsumerStatefulWidget {
  /// The task being edited, or null to create a new one.
  final Task? task;

  const TaskFormSheet({super.key, this.task});

  static Future<void> show(BuildContext context, {Task? task}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => TaskFormSheet(task: task),
    );
  }

  @override
  ConsumerState<TaskFormSheet> createState() => _TaskFormSheetState();
}

/// A subtask as edited in the form; [id] is null until it is saved.
class _SubtaskDraft {
  final int? id;
  final String title;
  bool isCompleted;

  _SubtaskDraft({this.id, required this.title, this.isCompleted = false});
}

class _TaskFormSheetState extends ConsumerState<TaskFormSheet> {
  static const _priorities = [1, 3, 5];
  static const _repeatCounts = [2, 3, 4, 5, 6, 8, 10, 12, 14, 16, 20, 26, 52];

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  final _subtaskInputController = TextEditingController();

  late DateTime _dueDate;
  late TimeOfDay _dueTime;
  late String _category;
  late int _priority;
  late int _estimatedMinutes;
  late bool _isRecurring;
  String _repeatEndMode = 'indefinite'; // 'indefinite', 'until_date', 'count'
  DateTime? _repeatUntilDate;
  int _repeatCount = 10;

  final List<_SubtaskDraft> _subtasks = [];
  final List<_SubtaskDraft> _originalSubtasks = [];

  bool get _isEditing => widget.task != null;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _titleController = TextEditingController(text: t?.title ?? '');
    _descController = TextEditingController(text: t?.description ?? '');

    if (t == null) {
      final defaults = ref.read(formDefaultsServiceProvider);
      _dueDate = defaults.lastTaskDueDate ?? DateTime.now().add(const Duration(days: 2));
      _dueTime = defaults.lastTaskDueTime ?? const TimeOfDay(hour: 23, minute: 59);
      _category = defaults.lastTaskCategory ?? 'schoolwork';
      _estimatedMinutes = defaults.lastTaskEstimatedMinutes ?? 120;
      _priority = 3;
      _isRecurring = false;
    } else {
      final activeDue = TimezoneService.instance.toActiveTime(t.dueDate, ref.read(settingsNotifierProvider));
      _dueDate = DateTime(activeDue.year, activeDue.month, activeDue.day);
      _dueTime = TimeOfDay(hour: activeDue.hour, minute: activeDue.minute);
      _category = t.category;
      _estimatedMinutes = t.estimatedMinutes ?? 120;
      // Older/synced rows may carry 2 or 4; snap to the nearest option shown
      _priority = _priorities.contains(t.priority) ? t.priority : (t.priority < 3 ? 1 : 5);
      _isRecurring = t.isRecurring;
      _parseRepeatEnd(t.rrule);
      _loadSubtasks(t.id);
    }
    _repeatUntilDate ??= _dueDate.add(const Duration(days: 90));
  }

  void _parseRepeatEnd(String? rrule) {
    if (rrule == null) return;
    final until = RegExp(r'UNTIL=(\d{8})').firstMatch(rrule);
    final count = RegExp(r'COUNT=(\d+)').firstMatch(rrule);
    if (until != null) {
      final s = until.group(1)!;
      _repeatEndMode = 'until_date';
      _repeatUntilDate = DateTime(int.parse(s.substring(0, 4)), int.parse(s.substring(4, 6)), int.parse(s.substring(6, 8)));
    } else if (count != null) {
      _repeatEndMode = 'count';
      _repeatCount = int.tryParse(count.group(1)!) ?? 10;
    }
  }

  Future<void> _loadSubtasks(int taskId) async {
    final rows = await ref.read(taskDaoProvider).getSubtasksForTask(taskId);
    if (!mounted) return;
    setState(() {
      for (final r in rows) {
        _subtasks.add(_SubtaskDraft(id: r.id, title: r.title, isCompleted: r.isCompleted));
        _originalSubtasks.add(_SubtaskDraft(id: r.id, title: r.title, isCompleted: r.isCompleted));
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _subtaskInputController.dispose();
    super.dispose();
  }

  String? _buildRrule() {
    if (!_isRecurring) return null;
    final baseRule = 'FREQ=WEEKLY;BYDAY=${_dayToRruleCode(_dueDate.weekday)}';
    if (_repeatEndMode == 'until_date' && _repeatUntilDate != null) {
      final u = _repeatUntilDate!;
      final uStr = '${u.year}${u.month.toString().padLeft(2, '0')}${u.day.toString().padLeft(2, '0')}T235959Z';
      return '$baseRule;UNTIL=$uStr';
    } else if (_repeatEndMode == 'count') {
      return '$baseRule;COUNT=$_repeatCount';
    }
    return baseRule;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    _addPendingSubtask(); // keep text typed into the subtask field but not yet added

    final activeDue = DateTime(_dueDate.year, _dueDate.month, _dueDate.day, _dueTime.hour, _dueTime.minute);
    final dueDateTime = TimezoneService.instance.fromActiveTime(activeDue, ref.read(settingsNotifierProvider));
    final description = _descController.text.trim().isNotEmpty ? Value(_descController.text.trim()) : const Value<String?>(null);
    final taskDao = ref.read(taskDaoProvider);

    late final int taskId;
    if (_isEditing) {
      taskId = widget.task!.id;
      await taskDao.updateTask(widget.task!.toCompanion(true).copyWith(
            title: Value(_titleController.text.trim()),
            category: Value(_category),
            priority: Value(_priority),
            description: description,
            dueDate: Value(dueDateTime),
            estimatedMinutes: Value(_estimatedMinutes),
            isRecurring: Value(_isRecurring),
            rrule: Value(_buildRrule()),
            updatedAt: Value(DateTime.now().toUtc()),
          ));
    } else {
      taskId = await taskDao.insertTask(TasksCompanion.insert(
        title: _titleController.text.trim(),
        category: Value(_category),
        dueDate: dueDateTime,
        description: description,
        priority: Value(_priority),
        isRecurring: Value(_isRecurring),
        rrule: Value(_buildRrule()),
        estimatedMinutes: Value(_estimatedMinutes),
      ));
      await ref.read(formDefaultsServiceProvider).saveTaskDefaults(
            dueDate: _dueDate,
            dueTime: _dueTime,
            estimatedMinutes: _estimatedMinutes,
            category: _category,
          );
    }

    await _saveSubtasks(taskDao, taskId);

    ref.invalidate(dashboardTasksProvider);
    ref.invalidate(incompleteTasksStreamProvider);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _saveSubtasks(TaskDao taskDao, int taskId) async {
    final keptIds = _subtasks.map((s) => s.id).whereType<int>().toSet();
    for (final original in _originalSubtasks) {
      if (!keptIds.contains(original.id)) await taskDao.deleteSubtask(original.id!);
    }
    for (final s in _subtasks) {
      if (s.id == null) {
        await taskDao.insertSubtask(SubtasksCompanion.insert(
          taskId: taskId,
          title: s.title,
          isCompleted: Value(s.isCompleted),
        ));
        continue;
      }
      final original = _originalSubtasks.firstWhere((o) => o.id == s.id);
      if (original.isCompleted != s.isCompleted) await taskDao.toggleSubtask(s.id!, s.isCompleted);
    }
  }

  void _addPendingSubtask() {
    final text = _subtaskInputController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _subtasks.add(_SubtaskDraft(title: text));
      _subtaskInputController.clear();
    });
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
    final categories = ref.watch(allCategoriesProvider).value ?? [];
    // Keep the dropdown valid if the task's category was deleted
    final categoryItems = [
      for (final cat in categories) DropdownMenuItem(value: cat.slug, child: Text('${cat.emoji} ${cat.name}')),
      if (categories.isNotEmpty && !categories.any((c) => c.slug == _category))
        DropdownMenuItem(value: _category, child: Text(_category)),
    ];

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
                  Text(
                    _isEditing ? 'Edit Task' : 'New Task',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Discard',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                autofocus: !_isEditing,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. OS Project Submission, Essay Draft',
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
                      isExpanded: true,
                      initialValue: categoryItems.isEmpty ? null : _category,
                      decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                      items: categoryItems,
                      onChanged: (val) {
                        if (val != null) setState(() => _category = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: _priority,
                      decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('🟢 Low')),
                        DropdownMenuItem(value: 3, child: Text('🟡 Medium')),
                        DropdownMenuItem(value: 5, child: Text('🔴 High')),
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
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(DateFormat('MMM d, yyyy').format(_dueDate)),
                      onPressed: () async {
                        final now = DateTime.now();
                        final first = now.subtract(const Duration(days: 365));
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _dueDate.isBefore(first) ? first : _dueDate,
                          firstDate: first,
                          lastDate: now.add(const Duration(days: 365 * 3)),
                        );
                        if (picked != null) setState(() => _dueDate = picked);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time, size: 16),
                      label: Text(_dueTime.format(context)),
                      onPressed: () async {
                        final picked = await showTimePicker(context: context, initialTime: _dueTime);
                        if (picked != null) setState(() => _dueTime = picked);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Repeats weekly'),
                subtitle: const Text('Completing it rolls the deadline forward a week'),
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
                            'Repeats until: ${DateFormat('MMM d, yyyy').format(_repeatUntilDate!)}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          trailing: const Icon(Icons.calendar_month, size: 20),
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _repeatUntilDate!.isBefore(_dueDate) ? _dueDate : _repeatUntilDate!,
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
                              value: _repeatCounts.contains(_repeatCount) ? _repeatCount : 10,
                              items: _repeatCounts.map((cnt) {
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
                  const Flexible(child: Text('Estimated time needed:')),
                  Text(_formatDuration(_estimatedMinutes), style: const TextStyle(fontWeight: FontWeight.bold)),
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
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 14),

              // Subtasks
              const Text('Subtasks (optional)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              for (final (idx, sub) in _subtasks.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: sub.isCompleted,
                          onChanged: (val) => setState(() => sub.isCompleted = val ?? false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sub.title,
                          style: TextStyle(
                            fontSize: 13,
                            decoration: sub.isCompleted ? TextDecoration.lineThrough : null,
                            color: sub.isCompleted ? Colors.grey : null,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                        tooltip: 'Remove subtask',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => setState(() => _subtasks.removeAt(idx)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _subtaskInputController,
                      decoration: const InputDecoration(
                        hintText: 'Add subtask (e.g. outline draft)...',
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
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: Text(_isEditing ? 'Save Changes' : 'Add Task', style: const TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
