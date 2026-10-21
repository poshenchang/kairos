// lib/ui/widgets/habit_form_sheet.dart
//
// Bottom sheet to create or edit a frequency-based habit
// (e.g. Personal research, Instrument practice).

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/form_defaults_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';

class HabitFormSheet extends ConsumerStatefulWidget {
  /// The habit being edited, or null to create a new one.
  final Habit? habit;

  const HabitFormSheet({super.key, this.habit});

  static Future<void> show(BuildContext context, {Habit? habit}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => HabitFormSheet(habit: habit),
    );
  }

  @override
  ConsumerState<HabitFormSheet> createState() => _HabitFormSheetState();
}

class _HabitPreset {
  final String emoji;
  final String label;
  final String title;
  final int frequency;
  final int minM;
  final int maxM;
  final String window;

  const _HabitPreset(this.emoji, this.label, this.title, this.frequency, this.minM, this.maxM, this.window);
}

const _presets = [
  _HabitPreset('🇯🇵', 'Language Learning', 'Language Learning (Duolingo/Practice)', 7, 20, 30, 'any'),
  _HabitPreset('🎙️', 'Daily Podcast', 'Daily Podcast / News', 7, 25, 45, 'morning'),
  _HabitPreset('📖', 'Daily Reading', 'Daily Reading / Paper Review', 7, 30, 60, 'evening'),
  _HabitPreset('🧘', 'Daily Meditation', 'Mindfulness & Meditation', 7, 15, 25, 'morning'),
  _HabitPreset('🎹', 'Instrument Practice', 'Instrument / Piano Practice', 4, 30, 60, 'afternoon'),
];

class _HabitFormSheetState extends ConsumerState<HabitFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descController;
  late final TextEditingController _minMinutesController;
  late final TextEditingController _maxMinutesController;

  late String _category;
  late int _targetFrequency;
  late bool _isDailyMode;
  late String _preferredWindow; // morning, afternoon, evening, any
  late String _daysFilter; // all, weekdays, weekends
  late bool _isActive;

  bool get _isEditing => widget.habit != null;

  @override
  void initState() {
    super.initState();
    final h = widget.habit;
    if (h == null) {
      final defaults = ref.read(formDefaultsServiceProvider);
      final duration = (defaults.lastHabitDuration ?? 60).toString();
      _titleController = TextEditingController();
      _descController = TextEditingController();
      _minMinutesController = TextEditingController(text: duration);
      _maxMinutesController = TextEditingController(text: duration);
      _category = defaults.lastHabitCategory ?? 'personal';
      _targetFrequency = 3;
      _preferredWindow = 'any';
      _daysFilter = 'all';
      _isActive = true;
    } else {
      _titleController = TextEditingController(text: h.title);
      _descController = TextEditingController(text: h.description ?? '');
      _minMinutesController = TextEditingController(text: h.minSessionMinutes.toString());
      _maxMinutesController = TextEditingController(text: h.maxSessionMinutes.toString());
      _category = h.category;
      _targetFrequency = h.targetFrequencyPerWeek;
      _preferredWindow = h.preferredWindow;
      _daysFilter = h.daysFilter;
      _isActive = h.isActive;
    }
    _isDailyMode = _targetFrequency == 7;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _minMinutesController.dispose();
    _maxMinutesController.dispose();
    super.dispose();
  }

  void _applyPreset(_HabitPreset p) {
    setState(() {
      _titleController.text = p.title;
      _category = 'personal';
      _isDailyMode = p.frequency == 7;
      _targetFrequency = p.frequency;
      _minMinutesController.text = p.minM.toString();
      _maxMinutesController.text = p.maxM.toString();
      _preferredWindow = p.window;
      _daysFilter = 'all';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final minM = int.tryParse(_minMinutesController.text.trim()) ?? 30;
    final maxM = int.tryParse(_maxMinutesController.text.trim()) ?? 60;
    final description = _descController.text.trim().isNotEmpty ? Value(_descController.text.trim()) : const Value<String?>(null);
    final habitDao = ref.read(habitDaoProvider);

    if (_isEditing) {
      await habitDao.updateHabit(widget.habit!.toCompanion(true).copyWith(
            title: Value(_titleController.text.trim()),
            category: Value(_category),
            description: description,
            targetFrequencyPerWeek: Value(_isDailyMode ? 7 : _targetFrequency),
            minSessionMinutes: Value(minM),
            maxSessionMinutes: Value(maxM < minM ? minM : maxM),
            preferredWindow: Value(_preferredWindow),
            daysFilter: Value(_daysFilter),
            isActive: Value(_isActive),
            updatedAt: Value(DateTime.now().toUtc()),
          ));
    } else {
      await habitDao.insertHabit(HabitsCompanion.insert(
        title: _titleController.text.trim(),
        category: Value(_category),
        description: description,
        targetFrequencyPerWeek: Value(_isDailyMode ? 7 : _targetFrequency),
        minSessionMinutes: Value(minM),
        maxSessionMinutes: Value(maxM < minM ? minM : maxM),
        preferredWindow: Value(_preferredWindow),
        daysFilter: Value(_daysFilter),
        isActive: Value(_isActive),
      ));
      await ref.read(formDefaultsServiceProvider).saveHabitDefaults(
            time: const TimeOfDay(hour: 9, minute: 0),
            durationMinutes: minM,
            category: _category,
          );
    }

    ref.invalidate(weeklyHabitCompletionsProvider);

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(allCategoriesProvider).value ?? [];
    // Keep the dropdown valid if the habit's category was deleted
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
                    _isEditing ? 'Edit Habit' : 'New Habit',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Discard',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              if (!_isEditing) ...[
                const SizedBox(height: 8),
                const Text(
                  'Quick Presets:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final p in _presets)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ActionChip(
                            avatar: Text(p.emoji),
                            label: Text(p.label),
                            onPressed: () => _applyPreset(p),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  hintText: 'e.g. Language Learning, Podcast, Piano, Reading',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                // Keyed on the value so presets update the displayed selection
                key: ValueKey('category-$_category'),
                initialValue: categoryItems.isEmpty ? null : _category,
                decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                items: categoryItems,
                onChanged: (val) {
                  if (val != null) setState(() => _category = val);
                },
              ),
              const SizedBox(height: 16),
              const Text('Cadence', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('🔥 Daily')),
                    ButtonSegment(value: false, label: Text('Times per week')),
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
                      Icon(Icons.auto_awesome, size: 16, color: Colors.purpleAccent),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'The schedule assistant fits one session into open gaps every day.',
                          style: TextStyle(fontSize: 12, color: Colors.purpleAccent, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Flexible(child: Text('Weekly target:')),
                    Text('$_targetFrequency × / week', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                Slider(
                  value: _targetFrequency.toDouble().clamp(1.0, 6.0),
                  min: 1,
                  max: 6,
                  divisions: 5,
                  label: '$_targetFrequency times/week',
                  onChanged: (val) => setState(() => _targetFrequency = val.toInt()),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('window-$_preferredWindow'),
                initialValue: _preferredWindow,
                decoration: const InputDecoration(
                  labelText: 'Preferred time window',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'any', child: Text('⚡ Any free time')),
                  DropdownMenuItem(value: 'morning', child: Text('🌅 Morning (06:00–12:00)')),
                  DropdownMenuItem(value: 'afternoon', child: Text('☀️ Afternoon (12:00–17:00)')),
                  DropdownMenuItem(value: 'evening', child: Text('🌙 Evening (17:00–22:00)')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _preferredWindow = val);
                },
              ),
              const SizedBox(height: 14),
              const Text('Days', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'all', label: Text('Every day')),
                    ButtonSegment(value: 'weekdays', label: Text('Mon–Fri')),
                    ButtonSegment(value: 'weekends', label: Text('Sat–Sun')),
                  ],
                  selected: {_daysFilter},
                  onSelectionChanged: (val) => setState(() => _daysFilter = val.first),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _minMinutesController,
                      decoration: const InputDecoration(labelText: 'Min minutes/session', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _maxMinutesController,
                      decoration: const InputDecoration(labelText: 'Max minutes/session', border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              if (_isEditing) ...[
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active in Schedule Assistant', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('When off, the assistant stops placing sessions for this habit.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  value: _isActive,
                  onChanged: (val) => setState(() => _isActive = val),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.check),
                  label: Text(_isEditing ? 'Save Changes' : 'Add Habit', style: const TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
