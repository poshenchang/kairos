// lib/ui/widgets/add_habit_dialog.dart
//
// Modal dialog to create a frequency-based habit (e.g. Personal research, Instrument practice).

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
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

  String _selectedCategory = 'personal';
  int _targetFrequency = 3; // 3x per week
  int _minMinutes = 30;
  int _maxMinutes = 60;
  String _preferredWindow = 'any'; // morning, afternoon, evening, any

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _saveHabit() async {
    if (!_formKey.currentState!.validate()) return;

    final habitDao = ref.read(habitDaoProvider);
    await habitDao.insertHabit(
      HabitsCompanion.insert(
        title: _titleController.text.trim(),
        category: Value(_selectedCategory),
        description: _descController.text.isNotEmpty
            ? Value(_descController.text.trim())
            : const Value(null),
        targetFrequencyPerWeek: Value(_targetFrequency),
        minSessionMinutes: Value(_minMinutes),
        maxSessionMinutes: Value(_maxMinutes),
        preferredWindow: Value(_preferredWindow),
      ),
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
              const SizedBox(height: 8),
              const Text(
                'For activities with no hard deadline but needing regular cadence (e.g. practicing piano, personal research, reading).',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Habit Title',
                  hintText: 'e.g. Piano Practice, Deep Research, Reading Papers',
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
              const SizedBox(height: 8),
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: _minMinutes.toString(),
                      decoration: const InputDecoration(
                        labelText: 'Min min/session',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (val) {
                        final parsed = int.tryParse(val);
                        if (parsed != null && parsed > 0) _minMinutes = parsed;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: _maxMinutes.toString(),
                      decoration: const InputDecoration(
                        labelText: 'Max min/session',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (val) {
                        final parsed = int.tryParse(val);
                        if (parsed != null && parsed > 0) _maxMinutes = parsed;
                      },
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

