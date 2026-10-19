// lib/ui/widgets/add_habit_dialog.dart
//
// Modal dialog to create a frequency-based habit (e.g. Personal research, Instrument practice).

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/form_defaults_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';

class AddHabitDialog extends ConsumerStatefulWidget {
  const AddHabitDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const AddHabitDialog(),
    );
  }

  @override
  ConsumerState<AddHabitDialog> createState() => _AddHabitDialogState();
}

class _AddHabitDialogState extends ConsumerState<AddHabitDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _minMinutesController = TextEditingController(text: '60');
  final _maxMinutesController = TextEditingController(text: '60');

  String _selectedCategory = 'personal';
  int _targetFrequency = 3; // 3x per week
  bool _isDailyMode = false;
  String _preferredWindow = 'any'; // morning, afternoon, evening, any
  String _daysFilter = 'all'; // all, weekdays, weekends

  @override
  void initState() {
    super.initState();
    final defaults = ref.read(formDefaultsServiceProvider);
    if (defaults.lastHabitCategory != null) {
      _selectedCategory = defaults.lastHabitCategory!;
    }
    if (defaults.lastHabitDuration != null) {
      _minMinutesController.text = defaults.lastHabitDuration.toString();
      _maxMinutesController.text = defaults.lastHabitDuration.toString();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _minMinutesController.dispose();
    _maxMinutesController.dispose();
    super.dispose();
  }

  void _applyPreset({
    required String title,
    required String category,
    required bool isDaily,
    required int frequency,
    required int minM,
    required int maxM,
    required String window,
    String daysFilter = 'all',
  }) {
    setState(() {
      _titleController.text = title;
      _selectedCategory = category;
      _isDailyMode = isDaily;
      _targetFrequency = frequency;
      _minMinutesController.text = minM.toString();
      _maxMinutesController.text = maxM.toString();
      _preferredWindow = window;
      _daysFilter = daysFilter;
    });
  }

  Future<void> _saveHabit() async {
    if (!_formKey.currentState!.validate()) return;

    final minM = int.tryParse(_minMinutesController.text.trim()) ?? 30;
    final maxM = int.tryParse(_maxMinutesController.text.trim()) ?? 60;

    final habitDao = ref.read(habitDaoProvider);
    await habitDao.insertHabit(
      HabitsCompanion.insert(
        title: _titleController.text.trim(),
        category: Value(_selectedCategory),
        description: _descController.text.isNotEmpty
            ? Value(_descController.text.trim())
            : const Value(null),
        targetFrequencyPerWeek: Value(_isDailyMode ? 7 : _targetFrequency),
        minSessionMinutes: Value(minM),
        maxSessionMinutes: Value(maxM < minM ? minM : maxM),
        preferredWindow: Value(_preferredWindow),
        daysFilter: Value(_daysFilter),
      ),
    );

    ref.invalidate(activeHabitsProvider);
    ref.invalidate(weeklyHabitCompletionsProvider);

    await ref.read(formDefaultsServiceProvider).saveHabitDefaults(
      time: const TimeOfDay(hour: 9, minute: 0),
      durationMinutes: minM,
      category: _selectedCategory,
    );

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
                    'New Habit / Frequency Activity',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Quick Presets
              const Text(
                'Quick Presets:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueAccent),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ActionChip(
                      avatar: const Text('🇯🇵'),
                      label: const Text('Language Learning'),
                      onPressed: () => _applyPreset(
                        title: 'Language Learning (Duolingo/Practice)',
                        category: 'personal',
                        isDaily: true,
                        frequency: 7,
                        minM: 20,
                        maxM: 30,
                        window: 'any',
                      ),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: const Text('🎙️'),
                      label: const Text('Daily Podcast'),
                      onPressed: () => _applyPreset(
                        title: 'Daily Podcast / News',
                        category: 'personal',
                        isDaily: true,
                        frequency: 7,
                        minM: 25,
                        maxM: 45,
                        window: 'morning',
                      ),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: const Text('📖'),
                      label: const Text('Daily Reading'),
                      onPressed: () => _applyPreset(
                        title: 'Daily Reading / Paper Review',
                        category: 'personal',
                        isDaily: true,
                        frequency: 7,
                        minM: 30,
                        maxM: 60,
                        window: 'evening',
                      ),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: const Text('🧘'),
                      label: const Text('Daily Meditation'),
                      onPressed: () => _applyPreset(
                        title: 'Mindfulness & Meditation',
                        category: 'personal',
                        isDaily: true,
                        frequency: 7,
                        minM: 15,
                        maxM: 25,
                        window: 'morning',
                      ),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      avatar: const Text('🎹'),
                      label: const Text('Instrument Practice'),
                      onPressed: () => _applyPreset(
                        title: 'Instrument / Piano Practice',
                        category: 'personal',
                        isDaily: false,
                        frequency: 4,
                        minM: 30,
                        maxM: 60,
                        window: 'afternoon',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Habit Title',
                  hintText: 'e.g. Language Learning, Podcast, Piano, Reading',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
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
              const SizedBox(height: 16),
              // Frequency Selector (Daily vs Custom Days)
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
                          'Daily Habit: Auto-scheduler will insert 1 session every single day into open gaps.',
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
                  labelText: 'Preferred Time Window for Auto-Scheduler',
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
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saveHabit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save Habit', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

