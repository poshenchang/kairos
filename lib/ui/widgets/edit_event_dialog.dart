// lib/ui/widgets/edit_event_dialog.dart
//
// Modal dialog to edit an existing calendar event.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/event_repository.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/form_defaults_service.dart';
import 'package:kairos/services/notification_service.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/timezone_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';

class EditEventDialog extends ConsumerStatefulWidget {
  final Event event;
  final DateTime? occurrenceDate;

  const EditEventDialog({super.key, required this.event, this.occurrenceDate});

  static Future<void> show(BuildContext context, Event event, {DateTime? occurrenceDate}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => EditEventDialog(event: event, occurrenceDate: occurrenceDate),
    );
  }

  @override
  ConsumerState<EditEventDialog> createState() => _EditEventDialogState();
}

class _EditEventDialogState extends ConsumerState<EditEventDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;

  late DateTime _selectedDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;

  late bool _isReminder;
  int? _notificationOffsetMinutes;

  late String _selectedCategory;
  late bool _isRecurring;
  late String _recurrenceFrequency;
  late String _repeatEndMode;
  DateTime? _repeatUntilDate;
  late int _repeatCount;
  late bool _requiresPrep;
  late int _prepMinutes;
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

  List<String> _cancelledDates = [];
  bool _isLoadingBase = false;

  @override
  void initState() {
    super.initState();
    final e = widget.event;
    _titleController = TextEditingController(text: e.title);
    _notesController = TextEditingController(text: e.notes ?? '');

    final settings = ref.read(settingsNotifierProvider);
    final activeStart = TimezoneService.instance.toActiveTime(e.startTime, settings);
    final activeEnd = TimezoneService.instance.toActiveTime(e.endTime, settings);
    _selectedDate = DateTime(activeStart.year, activeStart.month, activeStart.day);
    _startTime = TimeOfDay(hour: activeStart.hour, minute: activeStart.minute);
    _endTime = TimeOfDay(hour: activeEnd.hour, minute: activeEnd.minute);

    _isReminder = e.eventType == 'reminder';
    if (e.autoScheduleSource != null) {
      final match = RegExp(r'notify:(\d+)').firstMatch(e.autoScheduleSource!);
      if (match != null) {
        _notificationOffsetMinutes = int.tryParse(match.group(1)!);
      } else if (e.autoScheduleSource!.contains('notify:none')) {
        _notificationOffsetMinutes = null;
      } else if (_isReminder || e.isAutoScheduled) {
        _notificationOffsetMinutes = 0;
      }
    } else if (_isReminder || e.isAutoScheduled) {
      _notificationOffsetMinutes = 0;
    }

    _selectedCategory = e.category;
    _isRecurring = e.isRecurring;
    _requiresPrep = e.requiresPrep;
    _prepMinutes = e.prepMinutes ?? 60;
    _prepMinutesController = TextEditingController(text: '$_prepMinutes');

    _recurrenceFrequency = 'weekly';
    _repeatEndMode = 'indefinite';
    _repeatCount = 10;
    _repeatUntilDate = _selectedDate.add(const Duration(days: 90));

    _parseRrule(e.rrule);
    _cancelledDates = EventRepository.getCancelledDates(e.rrule);

    if (_isRecurring) {
      _loadBaseEvent();
    }
  }

  Future<void> _loadBaseEvent() async {
    setState(() => _isLoadingBase = true);
    final base = await ref.read(eventDaoProvider).getEventById(widget.event.id);
    if (base != null && mounted) {
      final settings = ref.read(settingsNotifierProvider);
      final activeStart = TimezoneService.instance.toActiveTime(base.startTime, settings);
      final activeEnd = TimezoneService.instance.toActiveTime(base.endTime, settings);
      setState(() {
        _selectedDate = DateTime(activeStart.year, activeStart.month, activeStart.day);
        _startTime = TimeOfDay(hour: activeStart.hour, minute: activeStart.minute);
        _endTime = TimeOfDay(hour: activeEnd.hour, minute: activeEnd.minute);
        _isReminder = base.eventType == 'reminder';
        if (base.autoScheduleSource != null) {
          final match = RegExp(r'notify:(\d+)').firstMatch(base.autoScheduleSource!);
          if (match != null) {
            _notificationOffsetMinutes = int.tryParse(match.group(1)!);
          } else if (base.autoScheduleSource!.contains('notify:none')) {
            _notificationOffsetMinutes = null;
          } else if (_isReminder || base.isAutoScheduled) {
            _notificationOffsetMinutes = 0;
          }
        } else if (_isReminder || base.isAutoScheduled) {
          _notificationOffsetMinutes = 0;
        }
        _requiresPrep = base.requiresPrep;
        _prepMinutes = base.prepMinutes ?? 60;
        _prepMinutesController.text = '$_prepMinutes';
        _cancelledDates = EventRepository.getCancelledDates(base.rrule);
        _parseRrule(base.rrule);
        _isLoadingBase = false;
      });
    } else if (mounted) {
      setState(() => _isLoadingBase = false);
    }
  }

  void _parseRrule(String? rrule) {
    if (rrule == null || rrule.isEmpty) return;
    final parts = rrule.split(';');
    for (final part in parts) {
      if (part.startsWith('FREQ=')) {
        final freq = part.substring(5).toUpperCase();
        if (freq == 'DAILY') _recurrenceFrequency = 'daily';
        if (freq == 'WEEKLY') _recurrenceFrequency = 'weekly';
      } else if (part.startsWith('UNTIL=')) {
        _repeatEndMode = 'until_date';
        final uStr = part.substring(6);
        if (uStr.length >= 8) {
          final y = int.tryParse(uStr.substring(0, 4)) ?? _selectedDate.year;
          final m = int.tryParse(uStr.substring(4, 6)) ?? _selectedDate.month;
          final d = int.tryParse(uStr.substring(6, 8)) ?? _selectedDate.day;
          _repeatUntilDate = DateTime(y, m, d);
        }
      } else if (part.startsWith('COUNT=')) {
        _repeatEndMode = 'count';
        _repeatCount = int.tryParse(part.substring(6)) ?? 10;
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _prepMinutesController.dispose();
    super.dispose();
  }

  Future<void> _updateEvent() async {
    if (!_formKey.currentState!.validate()) return;

    final activeStart = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _startTime.hour,
      _startTime.minute,
    );

    final activeEnd = _isReminder
        ? activeStart
        : DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
            _endTime.hour,
            _endTime.minute,
          );

    final settings = ref.read(settingsNotifierProvider);
    final startDateTime = TimezoneService.instance.fromActiveTime(activeStart, settings);
    final endDateTime = TimezoneService.instance.fromActiveTime(activeEnd, settings);

    // Conflict detection for time-block events
    if (!_isReminder) {
      final repo = ref.read(eventRepositoryProvider);
      final conflicts = await repo.getConflictingEvents(
        startDateTime,
        endDateTime,
        excludeEventId: widget.event.id,
      );
      if (conflicts.isNotEmpty && mounted) {
        final conflictList = conflicts
            .map((e) {
              final cStart = TimezoneService.instance.toActiveTime(e.startTime, settings);
              final cEnd = TimezoneService.instance.toActiveTime(e.endTime, settings);
              return '• ${e.title} (${DateFormat('h:mm a').format(cStart)} – ${DateFormat('h:mm a').format(cEnd)})';
            })
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
      if (_cancelledDates.isNotEmpty) {
        rrule = '$rrule;EXDATE=${_cancelledDates.join(',')}';
      }
    }

    final eventType = _isReminder ? 'reminder' : _selectedCategory;

    // Preserve the original entity source (habit:X, event:X:prep, task:X, etc.)
    String? baseEntitySource;
    if (widget.event.autoScheduleSource != null) {
      final nonNotifyTags = widget.event.autoScheduleSource!
          .split(';')
          .where((tag) => !tag.startsWith('notify:'))
          .toList();
      if (nonNotifyTags.isNotEmpty) {
        baseEntitySource = nonNotifyTags.join(';');
      }
    }

    String? finalAutoScheduleSource = baseEntitySource;
    if (_notificationOffsetMinutes != null) {
      finalAutoScheduleSource = baseEntitySource != null
          ? '$baseEntitySource;notify:$_notificationOffsetMinutes'
          : 'notify:$_notificationOffsetMinutes';
    } else {
      final isDerived = widget.event.isAutoScheduled ||
          (baseEntitySource != null &&
              (baseEntitySource.startsWith('habit:') ||
                  baseEntitySource.startsWith('event:') ||
                  baseEntitySource.startsWith('prep:') ||
                  baseEntitySource.startsWith('task:')));
      if (isDerived || _isReminder) {
        finalAutoScheduleSource = baseEntitySource != null
            ? '$baseEntitySource;notify:none'
            : 'notify:none';
      }
    }

    final eventDao = ref.read(eventDaoProvider);
    final updatedCompanion = widget.event.toCompanion(true).copyWith(
      title: Value(_titleController.text.trim()),
      category: Value(_selectedCategory),
      eventType: Value(eventType),
      startTime: Value(startDateTime),
      endTime: Value(endDateTime),
      isRecurring: Value(_isRecurring),
      rrule: Value(rrule),
      requiresPrep: Value(_requiresPrep && !_isReminder),
      prepMinutes: (_requiresPrep && !_isReminder) ? Value(_prepMinutes) : const Value(null),
      isAutoScheduled: Value(widget.event.isAutoScheduled),
      autoScheduleSource: Value(finalAutoScheduleSource),
      notes: _notesController.text.isNotEmpty
          ? Value(_notesController.text.trim())
          : const Value(null),
      updatedAt: Value(DateTime.now().toUtc()),
    );

    await eventDao.updateEvent(updatedCompanion);

    // Cache last-entered inputs for subsequent dialogs
    await ref.read(formDefaultsServiceProvider).saveEventDefaults(
      startDate: _selectedDate,
      startTime: _startTime,
      endTime: _endTime,
      category: _selectedCategory,
    );

    // Update notifications
    final notifService = ref.read(notificationServiceProvider);
    await notifService.cancelNotification(widget.event.id);
    final updatedEvent = await eventDao.getEventById(widget.event.id);
    if (updatedEvent != null) {
      await notifService.scheduleEventNotification(updatedEvent);
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
                    _isReminder ? 'Edit Reminder' : 'Edit Event',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              if (_isLoadingBase)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: LinearProgressIndicator(),
                ),
              const SizedBox(height: 12),

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
                      if (_isReminder && _notificationOffsetMinutes == null) {
                        _notificationOffsetMinutes = 0;
                      }
                    });
                  },
                ),
              ),
              const SizedBox(height: 14),

              if (_isRecurring) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.repeat, size: 18, color: Colors.blueAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Recurring Series (starts ${DateFormat('MMM d, yyyy').format(_selectedDate)})\n'
                          'Changes will apply across all occurrences.',
                          style: const TextStyle(fontSize: 12, color: Colors.blueAccent, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (widget.occurrenceDate != null && _isRecurring) ...[
                Card(
                  color: Colors.orange.withValues(alpha: 0.08),
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        const Icon(Icons.event_busy, size: 20, color: Colors.orange),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Cancel this day only?',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange),
                              ),
                              Text(
                                'Skip ${DateFormat('EEE, MMM d').format(widget.occurrenceDate!)} without changing other weeks.',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () async {
                            await ref.read(eventRepositoryProvider).cancelRecurringOccurrence(
                              widget.event.id,
                              widget.occurrenceDate!,
                            );
                            ref.invalidate(selectedDateEventsProvider);
                            ref.invalidate(todayEventsProvider);
                            ref.invalidate(allEventsStreamProvider);
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Cancelled occurrence for ${DateFormat('MMM d').format(widget.occurrenceDate!)}. You can restore it in All Events.'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          child: const Text('Cancel Day', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_cancelledDates.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Temporarily Cancelled Dates in this Series:',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: _cancelledDates.map((dStr) {
                          return Chip(
                            label: Text(dStr, style: const TextStyle(fontSize: 11)),
                            deleteIcon: const Icon(Icons.restore, size: 14, color: Colors.green),
                            onDeleted: () async {
                              await ref.read(eventRepositoryProvider).restoreRecurringOccurrence(widget.event.id, dStr);
                              setState(() => _cancelledDates.remove(dStr));
                              ref.invalidate(selectedDateEventsProvider);
                              ref.invalidate(todayEventsProvider);
                              ref.invalidate(allEventsStreamProvider);
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: _isReminder ? 'Reminder Title' : 'Event Title',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.event),
                ),
                validator: (val) => val == null || val.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 16),
              // Date picker
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text(_isRecurring ? 'Series Start Date' : 'Date'),
                subtitle: Text(DateFormat('EEEE, MMM d, yyyy').format(_selectedDate)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
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
              const SizedBox(height: 16),

              // Recurrence Switch
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Repeating / Recurring Event'),
                subtitle: const Text('Repeat on cadence (e.g. weekly classes, daily habits)'),
                value: _isRecurring,
                onChanged: (val) => setState(() => _isRecurring = val),
              ),
              if (_isRecurring) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Frequency:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'weekly', label: Text('Weekly')),
                        ButtonSegment(value: 'daily', label: Text('Daily (Habit)')),
                      ],
                      selected: {_recurrenceFrequency},
                      onSelectionChanged: (val) => setState(() => _recurrenceFrequency = val.first),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Repeat Until:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'indefinite', label: Text('Forever')),
                        ButtonSegment(value: 'until_date', label: Text('Until Date')),
                        ButtonSegment(value: 'count', label: Text('N Times')),
                      ],
                      selected: {_repeatEndMode},
                      onSelectionChanged: (val) => setState(() => _repeatEndMode = val.first),
                    ),
                  ],
                ),
                if (_repeatEndMode == 'until_date') ...[
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_busy, color: Colors.purple),
                    title: const Text('Stop repeating after date'),
                    subtitle: Text(
                      _repeatUntilDate != null
                          ? DateFormat('EEEE, MMM d, yyyy').format(_repeatUntilDate!)
                          : 'Select end date',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _repeatUntilDate ?? _selectedDate.add(const Duration(days: 90)),
                        firstDate: _selectedDate,
                        lastDate: _selectedDate.add(const Duration(days: 365 * 5)),
                      );
                      if (picked != null) setState(() => _repeatUntilDate = picked);
                    },
                  ),
                ],
                if (_repeatEndMode == 'count') ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Text('Total occurrences:'),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _repeatCount > 1 ? () => setState(() => _repeatCount--) : null,
                      ),
                      Text('$_repeatCount', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => setState(() => _repeatCount++),
                      ),
                    ],
                  ),
                ],
              ],
              if (!_isReminder) ...[
                const SizedBox(height: 12),
                // Requires prep
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Requires Preparation Block'),
                  subtitle: const Text('Include in scheduler sidebar for exam / interview prep'),
                  value: _requiresPrep,
                  onChanged: (val) => setState(() => _requiresPrep = val),
                ),
                if (_requiresPrep) ...[
                  const SizedBox(height: 6),
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes / Location',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.notes),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _updateEvent,
                  icon: const Icon(Icons.check),
                  label: const Text('Save Event Changes', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
