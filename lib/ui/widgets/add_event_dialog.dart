// lib/ui/widgets/add_event_dialog.dart
//
// Modal dialog to create or schedule a new event or quick reminder.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/form_defaults_service.dart';
import 'package:kairos/services/notification_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';

class AddEventDialog extends ConsumerStatefulWidget {
  final DateTime? initialDate;
  final TimeOfDay? initialStartTime;
  final TimeOfDay? initialEndTime;

  const AddEventDialog({
    super.key,
    this.initialDate,
    this.initialStartTime,
    this.initialEndTime,
  });

  static Future<void> show(
    BuildContext context, {
    DateTime? initialDate,
    TimeOfDay? initialStartTime,
    TimeOfDay? initialEndTime,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AddEventDialog(
        initialDate: initialDate,
        initialStartTime: initialStartTime,
        initialEndTime: initialEndTime,
      ),
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

  bool _isReminder = false;
  int? _notificationOffsetMinutes; // null, 0, 5, 10, 15, 30, 60, 1440

  String _selectedCategory = 'schoolwork';
  bool _isRecurring = false;
  String _recurrenceFrequency = 'weekly'; // 'daily' or 'weekly'
  String _repeatEndMode = 'indefinite'; // 'indefinite', 'until_date', 'count'
  DateTime? _repeatUntilDate;
  int _repeatCount = 10;
  bool _requiresPrep = false;
  int _prepMinutes = 60;
  late final TextEditingController _prepMinutesController;

  static const List<int> _prepTicks = [30, 60, 120, 240, 480, 720, 1440];

  double _prepMinutesToSliderValue(int minutes) {
    final clamped = minutes.clamp(_prepTicks.first, _prepTicks.last);
    for (int i = 0; i < _prepTicks.length - 1; i++) {
      if (clamped <= _prepTicks[i + 1]) {
        final range = _prepTicks[i + 1] - _prepTicks[i];
        final frac = (clamped - _prepTicks[i]) / range;
        return i + frac;
      }
    }
    return (_prepTicks.length - 1).toDouble();
  }

  String _formatPrepDuration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (mins == 0) return '$hours hr${hours > 1 ? 's' : ''}';
    return '$hours hr${hours > 1 ? 's' : ''} $mins min';
  }

  @override
  void initState() {
    super.initState();
    _prepMinutesController = TextEditingController(text: '$_prepMinutes');
    final defaults = ref.read(formDefaultsServiceProvider);
    if (widget.initialDate != null) {
      _selectedDate = DateTime(widget.initialDate!.year, widget.initialDate!.month, widget.initialDate!.day);
      _startTime = widget.initialStartTime ?? TimeOfDay(hour: widget.initialDate!.hour, minute: widget.initialDate!.minute);
      _endTime = widget.initialEndTime ?? TimeOfDay(hour: (_startTime.hour + 1) % 24, minute: _startTime.minute);
    } else {
      _selectedDate = defaults.lastEventStartDate ?? DateTime.now();
      _startTime = defaults.lastEventStartTime ?? const TimeOfDay(hour: 10, minute: 0);
      _endTime = defaults.lastEventEndTime ?? const TimeOfDay(hour: 11, minute: 30);
    }
    _selectedCategory = defaults.lastEventCategory ?? 'schoolwork';
    _repeatUntilDate = _selectedDate.add(const Duration(days: 90));
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _prepMinutesController.dispose();
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

    final endDateTime = _isReminder
        ? startDateTime
        : DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
            _endTime.hour,
            _endTime.minute,
          );

    // Conflict detection for time-block events
    if (!_isReminder) {
      final repo = ref.read(eventRepositoryProvider);
      final conflicts = await repo.getConflictingEvents(startDateTime, endDateTime);
      if (conflicts.isNotEmpty && mounted) {
        final conflictList = conflicts
            .map((e) =>
                '• ${e.title} (${DateFormat('h:mm a').format(e.startTime)} – ${DateFormat('h:mm a').format(e.endTime)})')
            .join('\n');

        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                SizedBox(width: 8),
                Text('Schedule Conflict'),
              ],
            ),
            content: Text(
              'This event overlaps with existing scheduled events:\n\n'
              '$conflictList\n\n'
              'Do you want to save this event anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Go Back'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save Anyway'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }
    }

    String? rrule;
    if (_isRecurring) {
      final baseRule = _recurrenceFrequency == 'daily'
          ? 'FREQ=DAILY'
          : 'FREQ=WEEKLY;BYDAY=${_dayToRruleCode(_selectedDate.weekday)}';
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

    final eventType = _isReminder ? 'reminder' : _selectedCategory;
    final autoScheduleSource = _notificationOffsetMinutes != null
        ? 'notify:$_notificationOffsetMinutes'
        : null;

    final eventDao = ref.read(eventDaoProvider);
    final eventId = await eventDao.insertEvent(
      EventsCompanion.insert(
        title: _titleController.text.trim(),
        category: Value(_selectedCategory),
        eventType: Value(eventType),
        startTime: startDateTime,
        endTime: endDateTime,
        isRecurring: Value(_isRecurring),
        rrule: Value(rrule),
        requiresPrep: Value(_requiresPrep && !_isReminder),
        prepMinutes: (_requiresPrep && !_isReminder) ? Value(_prepMinutes) : const Value(null),
        autoScheduleSource: Value(autoScheduleSource),
        notes: _notesController.text.isNotEmpty
            ? Value(_notesController.text.trim())
            : const Value(null),
      ),
    );

    // Cache last-entered inputs for subsequent dialogs
    await ref.read(formDefaultsServiceProvider).saveEventDefaults(
      startDate: _selectedDate,
      startTime: _startTime,
      endTime: _endTime,
      category: _selectedCategory,
    );

    // Schedule notification if selected
    if (autoScheduleSource != null) {
      final savedEvent = await eventDao.getEventById(eventId);
      if (savedEvent != null) {
        await ref.read(notificationServiceProvider).scheduleEventNotification(savedEvent);
      }
    }

    ref.invalidate(selectedDateEventsProvider);
    ref.invalidate(todayEventsProvider);
    ref.invalidate(allEventsStreamProvider);

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
                  Text(
                    _isReminder ? 'New Reminder' : 'New Event',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Event vs. Reminder Toggle
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      icon: Icon(Icons.calendar_today, size: 16),
                      label: Text('Calendar Event'),
                    ),
                    ButtonSegment(
                      value: true,
                      icon: Icon(Icons.notifications_active, size: 16),
                      label: Text('Quick Reminder'),
                    ),
                  ],
                  selected: {_isReminder},
                  onSelectionChanged: (s) {
                    setState(() {
                      _isReminder = s.first;
                      if (_isReminder) {
                        _notificationOffsetMinutes = 0; // Default notify at start for reminders
                      } else {
                        _notificationOffsetMinutes = null; // Default no reminder for standard events
                      }
                    });
                  },
                ),
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: _isReminder ? 'Reminder Title' : 'Event Title',
                  hintText: _isReminder
                      ? 'e.g. Call dentist, Submit timesheet, Take medicine'
                      : 'e.g. Distributed Systems Lecture, Gym, Tech Interview',
                  border: const OutlineInputBorder(),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 14),

              // Category Selector
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
              const SizedBox(height: 14),

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
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (picked != null) setState(() => _selectedDate = picked);
                },
              ),

              // Time pickers: Single time for reminders, start & end for events
              if (_isReminder)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: Text('Reminder Time: ${_startTime.format(context)}'),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _startTime,
                      );
                      if (picked != null) setState(() => _startTime = picked);
                    },
                  ),
                )
              else
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
              const SizedBox(height: 14),

              // Notification Settings
              DropdownButtonFormField<int?>(
                initialValue: _notificationOffsetMinutes,
                decoration: const InputDecoration(
                  labelText: 'Notification Alert',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.notifications_active_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('No notification')),
                  DropdownMenuItem(value: 0, child: Text('At start (0 min)')),
                  DropdownMenuItem(value: 5, child: Text('5 minutes before')),
                  DropdownMenuItem(value: 10, child: Text('10 minutes before')),
                  DropdownMenuItem(value: 15, child: Text('15 minutes before')),
                  DropdownMenuItem(value: 30, child: Text('30 minutes before')),
                  DropdownMenuItem(value: 60, child: Text('1 hour before')),
                  DropdownMenuItem(value: 1440, child: Text('1 day before')),
                ],
                onChanged: (val) => setState(() => _notificationOffsetMinutes = val),
              ),
              const SizedBox(height: 12),

              // Recurrence Switch & Options
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Repeats Regularly'),
                subtitle: Text(_isRecurring
                    ? (_recurrenceFrequency == 'daily'
                        ? 'Repeats every day'
                        : 'Repeats weekly every ${DateFormat('EEEE').format(_selectedDate)}')
                    : 'Does not repeat (One-off)'),
                value: _isRecurring,
                onChanged: (val) => setState(() => _isRecurring = val),
              ),
              if (_isRecurring) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 8.0, bottom: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cadence:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        segments: [
                          const ButtonSegment(value: 'daily', label: Text('Daily (Every day)')),
                          ButtonSegment(
                            value: 'weekly',
                            label: Text('Weekly (${DateFormat('EEE').format(_selectedDate)})'),
                          ),
                        ],
                        selected: {_recurrenceFrequency},
                        onSelectionChanged: (s) => setState(() => _recurrenceFrequency = s.first),
                      ),
                      const SizedBox(height: 12),
                      const Text('Repeat ends:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        segments: [
                          const ButtonSegment(value: 'indefinite', label: Text('Never')),
                          const ButtonSegment(value: 'until_date', label: Text('Until Date')),
                          ButtonSegment(
                            value: 'count',
                            label: Text(_recurrenceFrequency == 'daily' ? 'N Days' : 'N Weeks'),
                          ),
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
                              value: (_recurrenceFrequency == 'daily' && ![7, 14, 21, 30, 60, 90, 180, 365].contains(_repeatCount))
                                  ? 30
                                  : ((_recurrenceFrequency == 'weekly' && ![2, 3, 4, 5, 6, 8, 10, 12, 14, 16, 20, 26, 52].contains(_repeatCount))
                                      ? 10
                                      : _repeatCount),
                              items: (_recurrenceFrequency == 'daily'
                                      ? [7, 14, 21, 30, 60, 90, 180, 365]
                                      : [2, 3, 4, 5, 6, 8, 10, 12, 14, 16, 20, 26, 52])
                                  .map((n) {
                                return DropdownMenuItem(
                                  value: n,
                                  child: Text(_recurrenceFrequency == 'daily'
                                      ? '$n days'
                                      : '$n weeks'),
                                );
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

              if (!_isReminder) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Requires Preparation Block'),
                  subtitle: const Text('Include in scheduler sidebar for exam / interview prep'),
                  value: _requiresPrep,
                  onChanged: (val) => setState(() => _requiresPrep = val),
                ),
                if (_requiresPrep) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total Preparation Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('Up to 24h total prep time', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        ),
                        Text(
                          _formatPrepDuration(_prepMinutes),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.purpleAccent),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 85,
                          height: 38,
                          child: TextFormField(
                            controller: _prepMinutesController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              suffixText: 'min',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (val) {
                              final parsed = int.tryParse(val);
                              if (parsed != null && parsed >= 15 && parsed <= 1440) {
                                setState(() => _prepMinutes = parsed);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Slider(
                    value: _prepMinutesToSliderValue(_prepMinutes),
                    min: 0.0,
                    max: 6.0,
                    divisions: 6,
                    label: _formatPrepDuration(_prepMinutes),
                    onChanged: (val) {
                      final index = val.round();
                      final mins = _prepTicks[index];
                      setState(() {
                        _prepMinutes = mins;
                        _prepMinutesController.text = '$mins';
                      });
                    },
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('30m', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('1h', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('2h', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('4h', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('8h', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('12h', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('24h', style: TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],

              const SizedBox(height: 8),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes / Location (Optional)',
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
                  child: Text(_isReminder ? 'Save Reminder' : 'Save Event', style: const TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
