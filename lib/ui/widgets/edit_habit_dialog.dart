// lib/ui/widgets/edit_habit_dialog.dart
//
// Modal dialog to edit an existing frequency-based habit.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/ui/providers/app_providers.dart';

class EditHabitDialog extends ConsumerStatefulWidget {
  final Habit habit;

  const EditHabitDialog({super.key, required this.habit});

  static Future<void> show(BuildContext context, Habit habit) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => EditHabitDialog(habit: habit),
    );
  }

  @override
  ConsumerState<EditHabitDialog> createState() => _EditHabitDialogState();
}

class _EditHabitDialogState extends ConsumerState<EditHabitDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late final TextEditingController _minMinutesController;
  late final TextEditingController _maxMinutesController;

  late String _selectedCategory;
  late int _targetFrequency;
  late bool _isDailyMode;
  late String _preferredWindow;
  late String _daysFilter;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    _titleController = TextEditingController(text: h.title);
    _descController = TextEditingController(text: h.description ?? '');
    _minMinutesController = TextEditingController(text: h.minSessionMinutes.toString());
    _maxMinutesController = TextEditingController(text: h.maxSessionMinutes.toString());
    _selectedCategory = h.category;
    _targetFrequency = h.targetFrequencyPerWeek;
    _isDailyMode = h.targetFrequencyPerWeek == 7;
    _preferredWindow = h.preferredWindow;
    _daysFilter = h.daysFilter;
    _isActive = h.isActive;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _minMinutesController.dispose();
    _maxMinutesController.dispose();
    super.dispose();
  }

  Future<void> _updateHabit() async {
    if (!_formKey.currentState!.validate()) return;

    final minM = int.tryParse(_minMinutesController.text.trim()) ?? 30;
    final maxM = int.tryParse(_maxMinutesController.text.trim()) ?? 60;

    final habitDao = ref.read(habitDaoProvider);
    final updatedCompanion = widget.habit.toCompanion(true).copyWith(
      title: Value(_titleController.text.trim()),
      category: Value(_selectedCategory),
      description: _descController.text.isNotEmpty
          ? Value(_descController.text.trim())
          : const Value(null),
      targetFrequencyPerWeek: Value(_isDailyMode ? 7 : _targetFrequency),
      minSessionMinutes: Value(minM),
      maxSessionMinutes: Value(maxM < minM ? minM : maxM),
      preferredWindow: Value(_preferredWindow),
      daysFilter: Value(_daysFilter),
      isActive: Value(_isActive),
      updatedAt: Value(DateTime.now().toUtc()),
    );

    await habitDao.updateHabit(updatedCompanion);

    ref.invalidate(allHabitsProvider);
    ref.invalidate(activeHabitsProvider);
    ref.invalidate(weeklyHabitCompletionsProvider);

    if (mounted) Navigator.of(context).pop();
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
                    'Edit Habit / Frequency Activity',
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
                  labelText: 'Habit Title',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.repeat),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: 'Description / Goal notes (optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.notes),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category_outlined),
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
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Cadence:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('🔥 Daily (7×/wk)')),
                      ButtonSegment(value: false, label: Text('Custom Days')),
                    ],
                    selected: {_isDailyMode},
                    onSelectionChanged: (s) {
                      setState(() {
                        _isDailyMode = s.first;
                        if (_isDailyMode) {
                          _targetFrequency = 7;
                        } else if (_targetFrequency == 7) {
                          _targetFrequency = 3;
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_isDailyMode)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.purple.withValues(alpha: 0.25)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 16, color: Colors.purple),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Daily Habit: Schedule assistant will insert 1 session every single day into open gaps.',
                          style: TextStyle(fontSize: 12, color: Colors.purple, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Weekly Target Frequency:'),
                    Text('$_targetFrequency × / week', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                Slider(
                  value: _targetFrequency.toDouble(),
                  min: 1,
                  max: 7,
                  divisions: 6,
                  label: '$_targetFrequency times/week',
                  onChanged: (val) => setState(() => _targetFrequency = val.toInt()),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _preferredWindow,
                decoration: const InputDecoration(
                  labelText: 'Preferred Time Window for Schedule Assistant',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'any', child: Text('⚡ Any Free Time')),
                  DropdownMenuItem(value: 'morning', child: Text('🌅 Morning (06:00 - 12:00)')),
                  DropdownMenuItem(value: 'afternoon', child: Text('☀️ Afternoon (12:00 - 17:00)')),
                  DropdownMenuItem(value: 'evening', child: Text('🌙 Evening (17:00 - 22:00)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _preferredWindow = val);
                },
              ),
              const SizedBox(height: 14),
              const Text('Target Days:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'all',
                    label: Text('All Days (Mon–Sun)', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.calendar_today, size: 14),
                  ),
                  ButtonSegment(
                    value: 'weekdays',
                    label: Text('Weekdays (Mon–Fri)', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.work_outline, size: 14),
                  ),
                  ButtonSegment(
                    value: 'weekends',
                    label: Text('Weekends (Sat–Sun)', style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.weekend_outlined, size: 14),
                  ),
                ],
                selected: {_daysFilter},
                onSelectionChanged: (val) => setState(() => _daysFilter = val.first),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _minMinutesController,
                      decoration: const InputDecoration(
                        labelText: 'Min min/session',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _maxMinutesController,
                      decoration: const InputDecoration(
                        labelText: 'Max min/session',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Habit Active in Schedule Assistant', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('When disabled, the assistant will pause placing sessions for this habit.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                value: _isActive,
                onChanged: (val) => setState(() => _isActive = val),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _updateHabit,
                  icon: const Icon(Icons.check),
                  label: const Text('Save Habit Changes', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
