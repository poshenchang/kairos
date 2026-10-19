// lib/ui/screens/calendar/widgets/timetable_view.dart
//
// Interactive weekly/multi-day timetable grid with:
// - Vertical hour axis (6:00 AM – 11:00 PM)
// - Horizontal day scrolling (scroll right for future dates)
// - Solid colors for fixed schedules & deadlines; translucent borders for auto-scheduled events
// - Quick date picker navigation

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/notification_service.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/timezone_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/screens/calendar/widgets/drag_schedule_item.dart';
import 'package:kairos/ui/widgets/add_event_dialog.dart';
import 'package:kairos/ui/widgets/edit_event_dialog.dart';

class TimetableView extends ConsumerStatefulWidget {
  final DateTime anchorDate;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<DateTime>? onVisibleMonthChanged;

  const TimetableView({
    super.key,
    required this.anchorDate,
    required this.onDateSelected,
    this.onVisibleMonthChanged,
  });

  @override
  ConsumerState<TimetableView> createState() => _TimetableViewState();
}

class _TimetableViewState extends ConsumerState<TimetableView> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();
  late final ScrollController _headerScrollController = ScrollController();

  bool _isSyncingHorizontal = false;

  static const double _hourHeight = 60.0;
  static const int _startHour = 6;  // 6:00 AM
  static const int _endHour = 23;   // 11:00 PM
  static const double _timeGutterWidth = 55.0;
  static const double _dayColumnWidth = 140.0;
  static const int _pastDays = 60; // 60 days in past (2 months)
  static const int _futureDays = 730; // 730 days in future (2 full years)
  static const int _totalDays = _pastDays + _futureDays;

  late DateTime _baseSunday;
  late DateTime _startDate;
  int _lastReportedMonth = -1;
  int _lastReportedYear = -1;
  Future<List<Event>>? _eventsFuture;

  @override
  void initState() {
    super.initState();
    _computeBaseDates();
    _eventsFuture = _loadEvents();

    _horizontalController.addListener(_onBodyScroll);
    _headerScrollController.addListener(_onHeaderScroll);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentHour();
      _scrollToAnchorDate(animate: false);
      _onScrollUpdateVisibleMonth();
    });
  }

  Future<List<Event>> _loadEvents() {
    final rangeStart = _startDate.subtract(const Duration(days: 7));
    final rangeEnd = _startDate.add(const Duration(days: _totalDays + 7));
    return ref.read(eventRepositoryProvider).getExpandedEventsInRange(rangeStart, rangeEnd);
  }

  void _refreshEvents() {
    if (mounted) {
      setState(() {
        _eventsFuture = _loadEvents();
      });
    }
  }

  void _onBodyScroll() {
    if (_isSyncingHorizontal) return;
    _isSyncingHorizontal = true;
    if (_headerScrollController.hasClients &&
        _headerScrollController.offset != _horizontalController.offset) {
      _headerScrollController.jumpTo(_horizontalController.offset);
    }
    _isSyncingHorizontal = false;
    _onScrollUpdateVisibleMonth();
  }

  void _onHeaderScroll() {
    if (_isSyncingHorizontal) return;
    _isSyncingHorizontal = true;
    if (_horizontalController.hasClients &&
        _horizontalController.offset != _headerScrollController.offset) {
      _horizontalController.jumpTo(_headerScrollController.offset);
    }
    _isSyncingHorizontal = false;
    _onScrollUpdateVisibleMonth();
  }

  void _onScrollUpdateVisibleMonth() {
    if (!_horizontalController.hasClients) return;
    final offset = _horizontalController.offset;
    final dayIndex = (offset / _dayColumnWidth).floor().clamp(0, _totalDays - 1);
    final visibleDay = _startDate.add(Duration(days: dayIndex));
    if (visibleDay.month != _lastReportedMonth || visibleDay.year != _lastReportedYear) {
      _lastReportedMonth = visibleDay.month;
      _lastReportedYear = visibleDay.year;
      widget.onVisibleMonthChanged?.call(visibleDay);
    }
  }

  @override
  void didUpdateWidget(covariant TimetableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.anchorDate != oldWidget.anchorDate) {
      final daysDiff = widget.anchorDate.difference(_startDate).inDays;
      if (daysDiff < 0 || daysDiff >= _totalDays) {
        _computeBaseDates();
        _eventsFuture = _loadEvents();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToAnchorDate(animate: false);
          _onScrollUpdateVisibleMonth();
        });
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToAnchorDate(animate: true);
          _onScrollUpdateVisibleMonth();
        });
      }
    }
  }

  void _computeBaseDates() {
    // Week starts on Sunday! (weekday 7 in Dart % 7 = 0)
    final daysBack = widget.anchorDate.weekday % 7;
    final d = widget.anchorDate.subtract(Duration(days: daysBack));
    _baseSunday = DateTime(d.year, d.month, d.day);
    _startDate = _baseSunday.subtract(const Duration(days: _pastDays));
  }

  void _scrollToCurrentHour() {
    final now = DateTime.now();
    final currentHour = now.hour;
    if (currentHour >= _startHour && currentHour <= _endHour) {
      final targetOffset = (currentHour - _startHour) * _hourHeight - 40;
      if (_verticalController.hasClients) {
        _verticalController.jumpTo(targetOffset.clamp(0.0, (_endHour - _startHour) * _hourHeight));
      }
    }
  }

  void _scrollToAnchorDate({bool animate = true}) {
    final daysDiff = widget.anchorDate.difference(_startDate).inDays;
    if (daysDiff >= 0 && daysDiff < _totalDays && _horizontalController.hasClients) {
      final targetX = (daysDiff * _dayColumnWidth) - 20;
      final clamped = targetX.clamp(0.0, _horizontalController.position.maxScrollExtent);
      if (animate) {
        _horizontalController.animateTo(
          clamped,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _horizontalController.jumpTo(clamped);
      }
    }
  }

  @override
  void dispose() {
    _horizontalController.removeListener(_onBodyScroll);
    _headerScrollController.removeListener(_onHeaderScroll);
    _horizontalController.dispose();
    _headerScrollController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final settings = ref.watch(settingsNotifierProvider);

    // Listen for database changes to refresh events automatically
    ref.listen(allEventsStreamProvider, (_, __) {
      _refreshEvents();
    });

    return FutureBuilder<List<Event>>(
      future: _eventsFuture,
      builder: (context, snapshot) {
        final allEvents = snapshot.data ?? [];

        // Pre-group events by dateKey (YYYY-MM-DD) in active timezone for O(1) lookup during lazy rendering
        final eventsByDate = <String, List<Event>>{};
        for (final e in allEvents) {
          if (e.eventType == 'reminder') continue; // Reminders don't take up space in the timetable
          final activeStart = TimezoneService.instance.toActiveTime(e.startTime, settings);
          final dateKey = '${activeStart.year}-${activeStart.month.toString().padLeft(2, '0')}-${activeStart.day.toString().padLeft(2, '0')}';
          eventsByDate.putIfAbsent(dateKey, () => []).add(e);
        }

        return Column(
          children: [
            // Header: Day names & dates (Horizontally synchronized)
            _buildDaysHeader(context, isDark, settings),
            const Divider(height: 1),

            // Timetable body (Vertical & Horizontal scrollable)
            Expanded(
              child: SingleChildScrollView(
                controller: _verticalController,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Fixed Left Time Gutter (6 AM - 11 PM)
                    _buildTimeGutter(isDark),

                    // Scrollable Days & Events Grid (Virtualized!)
                    Expanded(
                      child: SizedBox(
                        height: (_endHour - _startHour + 1) * _hourHeight,
                        child: ListView.builder(
                          controller: _horizontalController,
                          scrollDirection: Axis.horizontal,
                          itemCount: _totalDays,
                          itemExtent: _dayColumnWidth,
                          itemBuilder: (context, index) {
                            final day = _startDate.add(Duration(days: index));
                            final isSelected = day.year == widget.anchorDate.year &&
                                day.month == widget.anchorDate.month &&
                                day.day == widget.anchorDate.day;

                            final dateKey = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
                            final dayEvents = eventsByDate[dateKey] ?? const [];

                            return _buildDayColumn(context, day, dayEvents, isSelected, isDark, settings);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDaysHeader(BuildContext context, bool isDark, SettingsState settings) {
    return Container(
      color: isDark ? const Color(0xFF131B2E) : const Color(0xFFF1F5F9),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: _timeGutterWidth,
            child: Center(
              child: IconButton(
                icon: const Icon(Icons.today, size: 16),
                tooltip: 'Jump to Today',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  final now = TimezoneService.instance.activeNow(settings);
                  widget.onDateSelected(now);
                  _scrollToAnchorDate();
                },
              ),
            ),
          ),
          Expanded(
            child: SizedBox(
              height: 58,
              child: ListView.builder(
                controller: _headerScrollController,
                scrollDirection: Axis.horizontal,
                itemCount: _totalDays,
                itemExtent: _dayColumnWidth,
                itemBuilder: (context, index) {
                  final day = _startDate.add(Duration(days: index));
                  final activeToday = TimezoneService.instance.activeNow(settings);
                  final isToday = _isSameDay(day, activeToday);
                  final isSelected = _isSameDay(day, widget.anchorDate);

                  return InkWell(
                    onTap: () => widget.onDateSelected(day),
                    child: Container(
                      width: _dayColumnWidth,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: isDark ? const Color(0xFF27324B) : const Color(0xFFE2E8F0),
                          ),
                          bottom: isSelected
                              ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
                              : BorderSide.none,
                        ),
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary.withValues(alpha: isDark ? 0.2 : 0.1)
                            : Colors.transparent,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('EEE').format(day), // Sun, Mon, Tue...
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: day.weekday == 7
                                  ? Colors.redAccent
                                  : (isToday ? Theme.of(context).colorScheme.primary : Colors.grey),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isToday
                                  ? Theme.of(context).colorScheme.primary
                                  : Colors.transparent,
                            ),
                            child: Text(
                              '${day.day}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isToday ? Colors.white : (isDark ? Colors.white : Colors.black87),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeGutter(bool isDark) {
    return SizedBox(
      width: _timeGutterWidth,
      child: Column(
        children: List.generate(_endHour - _startHour + 1, (index) {
          final hour = _startHour + index;
          final timeStr = DateFormat('h a').format(DateTime(2026, 1, 1, hour));

          return SizedBox(
            height: _hourHeight,
            child: Align(
              alignment: Alignment.topCenter,
              child: Text(
                timeStr,
                style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildDayColumn(
    BuildContext context,
    DateTime day,
    List<Event> events,
    bool isSelected,
    bool isDark,
    SettingsState settings,
  ) {
    const totalHeight = (_endHour - _startHour + 1) * _hourHeight;

    return Container(
      width: _dayColumnWidth,
      height: totalHeight,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(
            color: isDark ? const Color(0xFF27324B) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Stack(
        children: [
          // Hour grid lines
          ...List.generate(_endHour - _startHour + 1, (index) {
            return Positioned(
              top: index * _hourHeight,
              left: 0,
              right: 0,
              child: Container(
                height: 1,
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              ),
            );
          }),

          // Empty slot drag targets and tap detectors (every 30 minutes)
          ...List.generate((_endHour - _startHour + 1) * 2, (slotIndex) {
            final hour = _startHour + (slotIndex ~/ 2);
            final minute = (slotIndex % 2) * 30;
            final top = (slotIndex * 30.0 / 60.0) * _hourHeight;

            return Positioned(
              top: top,
              left: 0,
              right: 0,
              height: _hourHeight / 2,
              child: DragTarget<DragScheduleItem>(
                onWillAcceptWithDetails: (details) => true,
                builder: (context, candidateData, rejectedData) {
                  final hoveredItem = candidateData.isNotEmpty ? candidateData.first : null;
                  if (hoveredItem != null) {
                    final itemHeight = (hoveredItem.durationMinutes / 60.0) * _hourHeight;
                    final catColor = _getCategoryColor(hoveredItem.category);
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Container(
                        height: itemHeight,
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        decoration: BoxDecoration(
                          color: catColor.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: catColor, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: catColor.withValues(alpha: 0.25),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Text(
                          '+ Drop ${hoveredItem.title} (${hoveredItem.durationMinutes}m)',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  }

                  return InkWell(
                    onTap: () async {
                      widget.onDateSelected(day);
                      final initialStart = DateTime(day.year, day.month, day.day, hour, minute);
                      await AddEventDialog.show(
                        context,
                        initialDate: initialStart,
                        initialStartTime: TimeOfDay(hour: hour, minute: minute),
                        initialEndTime: TimeOfDay(hour: (hour + 1) % 24, minute: minute),
                      );
                      _refreshEvents();
                    },
                    child: const SizedBox.expand(),
                  );
                },
                onAcceptWithDetails: (details) async {
                  final item = details.data;
                  final activeStartTime = DateTime(day.year, day.month, day.day, hour, minute);
                  final activeEndTime = activeStartTime.add(Duration(minutes: item.durationMinutes));

                  final utcStartTime = TimezoneService.instance.fromActiveTime(activeStartTime, settings);
                  final utcEndTime = TimezoneService.instance.fromActiveTime(activeEndTime, settings);

                  widget.onDateSelected(day);

                  final eventDao = ref.read(eventDaoProvider);
                  final notificationService = ref.read(notificationServiceProvider);
                  final newId = await eventDao.insertEvent(
                    EventsCompanion.insert(
                      title: item.title,
                      startTime: utcStartTime,
                      endTime: utcEndTime,
                      category: drift.Value(item.category),
                      isAutoScheduled: const drift.Value(true),
                      autoScheduleSource: drift.Value(item.scheduleSource),
                      notes: item.subtask != null
                          ? drift.Value('Subtask for task: ${item.task?.title ?? ''}')
                          : const drift.Value(null),
                    ),
                  );

                  final savedEvent = await eventDao.getEventById(newId);
                  if (savedEvent != null) {
                    notificationService.scheduleEventNotification(savedEvent);
                  }

                  ref.invalidate(selectedDateEventsProvider);
                  ref.invalidate(todayEventsProvider);
                  ref.invalidate(allEventsStreamProvider);
                  _refreshEvents();

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).clearSnackBars();
                    final snackBar = SnackBar(
                      behavior: SnackBarBehavior.floating,
                      width: 440,
                      elevation: 8,
                      backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      duration: const Duration(seconds: 4),
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Scheduled "${item.title}" for ${DateFormat('EEE, MMM d • h:mm a').format(activeStartTime)}',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      action: SnackBarAction(
                        label: 'Undo',
                        textColor: Colors.amberAccent,
                        onPressed: () async {
                          await eventDao.deleteEvent(newId);
                          await notificationService.cancelNotification(newId);
                          ref.invalidate(selectedDateEventsProvider);
                          ref.invalidate(todayEventsProvider);
                          ref.invalidate(allEventsStreamProvider);
                          _refreshEvents();
                        },
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(snackBar);
                    // Explicit timer to guarantee dismissal within 4.5 seconds
                    Future.delayed(const Duration(milliseconds: 4500), () {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      }
                    });
                  }
                },
              ),
            );
          }),

          // Events positioned by time
          ...events.map((event) {
            return _buildEventTile(context, event, isDark, settings);
          }),
        ],
      ),
    );
  }

  Widget _buildEventTile(BuildContext context, Event event, bool isDark, SettingsState settings) {
    final start = TimezoneService.instance.toActiveTime(event.startTime, settings);
    final end = TimezoneService.instance.toActiveTime(event.endTime, settings);

    final startMinutes = (start.hour - _startHour) * 60 + start.minute;
    final durationMinutes = end.difference(start).inMinutes;

    final top = (startMinutes / 60.0) * _hourHeight;
    final height = ((durationMinutes.clamp(15, 600)) / 60.0) * _hourHeight;

    final baseColor = _getCategoryColor(event.category);
    final isAuto = event.isAutoScheduled;

    return Positioned(
      top: top,
      left: 2,
      right: 2,
      height: height.clamp(26.0, 400.0),
      child: GestureDetector(
        onTap: () => _showEventDetails(context, event, settings),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 6,
              vertical: height < 45 ? 2.0 : 4.0,
            ),
            decoration: BoxDecoration(
              // Solid color for fixed schedules/deadlines; Translucent color for scheduled sessions
              color: isAuto
                  ? baseColor.withValues(alpha: isDark ? 0.25 : 0.18)
                  : baseColor,
              borderRadius: BorderRadius.circular(8),
              border: isAuto
                  ? Border.all(color: baseColor, width: 1.5)
                  : Border.all(color: Colors.white24, width: 0.5),
              boxShadow: isAuto
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (isAuto)
                      const Padding(
                        padding: EdgeInsets.only(right: 3.0),
                        child: Icon(Icons.flash_on, size: 11, color: Colors.purpleAccent),
                      ),
                    Expanded(
                      child: Text(
                        event.title,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isAuto
                              ? (isDark ? Colors.white : Colors.black87)
                              : Colors.white,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (height >= 50)
                  Text(
                    '${DateFormat('h:mm a').format(start)} – ${DateFormat('h:mm a').format(end)}',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: isAuto
                          ? (isDark ? Colors.white70 : Colors.black54)
                          : Colors.white.withValues(alpha: 0.9),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEventDetails(BuildContext context, Event event, SettingsState settings) {
    String sessionTypeLabel = 'Scheduled Session';
    if (event.autoScheduleSource != null) {
      if (event.autoScheduleSource!.startsWith('habit:')) {
        sessionTypeLabel = 'Scheduled Habit Session';
      } else if (event.autoScheduleSource!.contains(':subtask:')) {
        sessionTypeLabel = 'Scheduled Subtask Focus Session';
      } else if (event.autoScheduleSource!.contains(':prep')) {
        sessionTypeLabel = 'Scheduled Exam / Interview Prep Session';
      } else if (event.autoScheduleSource!.startsWith('task:')) {
        sessionTypeLabel = 'Scheduled Task Focus Session';
      }
    }

    final activeStart = TimezoneService.instance.toActiveTime(event.startTime, settings);
    final activeEnd = TimezoneService.instance.toActiveTime(event.endTime, settings);
    final tzLabel = TimezoneService.instance.getActiveTimezoneLabel(settings);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    event.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent),
                  tooltip: 'Edit Event',
                  onPressed: () async {
                    Navigator.of(sheetContext).pop();
                    await EditEventDialog.show(context, event, occurrenceDate: activeStart);
                    ref.invalidate(selectedDateEventsProvider);
                    ref.invalidate(todayEventsProvider);
                    ref.invalidate(allEventsStreamProvider);
                    _refreshEvents();
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  tooltip: 'Delete Event',
                  onPressed: () async {
                    Navigator.of(sheetContext).pop();
                    await ref.read(eventDaoProvider).deleteEvent(event.id);
                    ref.invalidate(selectedDateEventsProvider);
                    ref.invalidate(todayEventsProvider);
                    ref.invalidate(allEventsStreamProvider);
                    _refreshEvents();
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${DateFormat('EEEE, MMMM d, yyyy').format(activeStart)}\n'
              '${DateFormat('h:mm a').format(activeStart)} – ${DateFormat('h:mm a').format(activeEnd)} ($tzLabel)',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (event.isAutoScheduled)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, size: 16, color: Colors.purpleAccent),
                    const SizedBox(width: 6),
                    Text(
                      sessionTypeLabel,
                      style: const TextStyle(fontSize: 12, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            if (event.isRecurring) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_busy, size: 16, color: Colors.orangeAccent),
                label: Text('Cancel Occurrence on ${DateFormat('EEE, MMM d').format(activeStart)}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orangeAccent,
                  side: const BorderSide(color: Colors.orangeAccent),
                ),
                onPressed: () async {
                  Navigator.of(sheetContext).pop();
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Cancel Occurrence'),
                      content: Text(
                        'Temporarily cancel "${event.title}" on ${DateFormat('EEEE, MMM d, yyyy').format(activeStart)}?\n\n'
                        'It will be hidden from the timetable, agenda, and dashboard. You can restore it anytime in All Events.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Keep'),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Cancel Occurrence'),
                        ),
                      ],
                    ),
                  );

                  if (confirm == true) {
                    await ref.read(eventRepositoryProvider).cancelRecurringOccurrence(event.id, activeStart);
                    ref.invalidate(selectedDateEventsProvider);
                    ref.invalidate(todayEventsProvider);
                    ref.invalidate(allEventsStreamProvider);
                    _refreshEvents();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Cancelled occurrence for ${DateFormat('MMM d').format(activeStart)}. You can restore it in All Events.'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    return switch (category.toLowerCase()) {
      'schoolwork' => const Color(0xFF4A90D9),
      'work' => const Color(0xFFE67E22),
      'research' => const Color(0xFF8E44AD),
      'personal' => const Color(0xFF27AE60),
      'social' => const Color(0xFFEC4899),
      'commute' || 'transportation' => const Color(0xFFE74C3C),
      _ => const Color(0xFF3B82F6),
    };
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

