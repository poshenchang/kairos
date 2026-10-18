// lib/ui/widgets/add_event_dialog.dart
//
// Modal dialog to create or schedule a new event.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/ui/providers/app_providers.dart';

class AddEventDialog extends ConsumerStatefulWidget {
  final DateTime? initialDate;

  const AddEventDialog({super.key, this.initialDate});

  static Future<void> show(BuildContext context, {DateTime? initialDate}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AddEventDialog(initialDate: initialDate),
    );
  }

  @override
  ConsumerState<AddEventDialog> createState() => _AddEventDialogState();
}

class _AddEventDialogState extends ConsumerState<AddEventDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();

  late DateTime _selectedDate;
  TimeOfDay _startTime = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 11, minute: 30);

  String _selectedCategory = 'schoolwork';
  String _eventType = 'lecture'; // lecture, gym, meeting, interview, commute, other
  bool _isRecurring = false;
  String _repeatEndMode = 'indefinite'; // 'indefinite', 'until_date', 'count'
  DateTime? _repeatUntilDate;
  int _repeatCount = 10;
  bool _requiresPrep = false;
  int _prepMinutes = 60;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    _repeatUntilDate = _selectedDate.add(const Duration(days: 90));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate()) return;

    final startDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _startTime.hour,
      _startTime.minute,
    );

    final endDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _endTime.hour,
      _endTime.minute,
    );

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

    final eventDao = ref.read(eventDaoProvider);
    await eventDao.insertEvent(
      EventsCompanion.insert(
        title: _titleController.text.trim(),
        category: Value(_selectedCategory),
        eventType: Value(_eventType),
        startTime: startDateTime,
        endTime: endDateTime,
        isRecurring: Value(_isRecurring),
        rrule: Value(rrule),
        requiresPrep: Value(_requiresPrep),
        prepMinutes: _requiresPrep ? Value(_prepMinutes) : const Value(null),
        notes: _notesController.text.isNotEmpty
            ? Value(_notesController.text.trim())
            : const Value(null),
      ),
    );

    if (mounted) Navigator.of(context).pop();
  }

  String _dayToRruleCode(int weekday) {
    const map = {1: 'MO', 2: 'TU', 3: 'WE', 4: 'TH', 5: 'FR', 6: 'SA', 7: 'SU'};
    return map[weekday] ?? 'MO';
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
                    'New Event',
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
                  labelText: 'Event Title',
                  hintText: 'e.g. Distributed Systems Lecture, Gym, Tech Interview',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              // Category & Event Type Row
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
                    child: DropdownButtonFormField<String>(
                      initialValue: _eventType,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'lecture', child: Text('🎓 Class/Lecture')),
                        DropdownMenuItem(value: 'gym', child: Text('💪 Gym/Workout')),
                        DropdownMenuItem(value: 'interview', child: Text('💼 Interview')),
                        DropdownMenuItem(value: 'meeting', child: Text('👥 Meeting')),
                        DropdownMenuItem(value: 'commute', child: Text('🚆 Commute/Transit')),
                        DropdownMenuItem(value: 'other', child: Text('📌 Other')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _eventType = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Date picker
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Date'),
                subtitle: Text(DateFormat('EEEE, MMM d, yyyy').format(_selectedDate)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) setState(() => _selectedDate = picked);
                },
              ),
              // Time pickers
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time),
                      label: Text('Start: ${_startTime.format(context)}'),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _startTime,
                        );
                        if (picked != null) setState(() => _startTime = picked);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.access_time_filled),
                      label: Text('End: ${_endTime.format(context)}'),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _endTime,
                        );
                        if (picked != null) setState(() => _endTime = picked);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Switches
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Repeats Weekly'),
                subtitle: Text('Repeats every ${DateFormat('EEEE').format(_selectedDate)}'),
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
                              value: _repeatCount,
                              items: [4, 6, 8, 10, 12, 14, 16, 20, 24].map((n) {
                                return DropdownMenuItem(value: n, child: Text('$n occurrences / weeks'));
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) setState(() => _repeatCount = val);
                              },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Requires Preparation Block'),
                subtitle: const Text('Auto-scheduler will insert prep time into free slots'),
                value: _requiresPrep,
                onChanged: (val) => setState(() => _requiresPrep = val),
              ),
              if (_requiresPrep) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Prep Time:'),
                      Text('$_prepMinutes minutes', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Slider(
                  value: _prepMinutes.toDouble(),
                  min: 30,
                  max: 240,
                  divisions: 7,
                  label: '$_prepMinutes min',
                  onChanged: (val) => setState(() => _prepMinutes = val.toInt()),
                ),
              ],
              const SizedBox(height: 8),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes / Location / Commute route',
                  hintText: 'e.g. Hometown to Campus (Train #321)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _saveEvent,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Save Event', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

