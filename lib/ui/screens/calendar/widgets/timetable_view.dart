// lib/ui/screens/calendar/widgets/timetable_view.dart
//
// Interactive weekly/multi-day timetable grid with:
// - Vertical hour axis (6:00 AM – 11:00 PM)
// - Horizontal day scrolling (scroll right for future dates)
// - Solid colors for fixed schedules & deadlines; translucent borders for auto-scheduled events
// - Quick date picker navigation

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/ui/theme/app_theme.dart';
import 'package:kairos/ui/widgets/add_event_dialog.dart';

class TimetableView extends ConsumerStatefulWidget {
  final DateTime anchorDate;
  final ValueChanged<DateTime> onDateSelected;

  const TimetableView({
    super.key,
    required this.anchorDate,
    required this.onDateSelected,
  });

  @override
  ConsumerState<TimetableView> createState() => _TimetableViewState();
}

class _TimetableViewState extends ConsumerState<TimetableView> {
  final ScrollController _horizontalController = ScrollController();
  final ScrollController _verticalController = ScrollController();

  static const double _hourHeight = 60.0;
  static const int _startHour = 6;  // 6:00 AM
  static const int _endHour = 23;   // 11:00 PM
  static const double _timeGutterWidth = 55.0;
  static const double _dayColumnWidth = 140.0;
  static const int _totalDays = 60; // 60 days scrollable forward/backward

  late DateTime _baseSunday;

  @override
  void initState() {
    super.initState();
    _computeBaseSunday();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentHour();
    });
  }

  @override
  void didUpdateWidget(covariant TimetableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.anchorDate != oldWidget.anchorDate) {
      _computeBaseSunday();
    }
  }

  void _computeBaseSunday() {
    // Week starts on Sunday! (weekday 7 in Dart % 7 = 0)
    final daysBack = widget.anchorDate.weekday % 7;
    final d = widget.anchorDate.subtract(Duration(days: daysBack));
    _baseSunday = DateTime(d.year, d.month, d.day);
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

  @override
  void dispose() {
    _horizontalController.dispose();
    _verticalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Fetch expanded events for the visible timetable window
    final rangeStart = _baseSunday.subtract(const Duration(days: 7));
    final rangeEnd = _baseSunday.add(const Duration(days: _totalDays));

    return FutureBuilder<List<Event>>(
      future: ref.read(eventRepositoryProvider).getExpandedEventsInRange(rangeStart, rangeEnd),
      builder: (context, snapshot) {
        final allEvents = snapshot.data ?? [];

        return Column(
          children: [
            // Header: Day names & dates (Horizontally synchronized)
            _buildDaysHeader(context, isDark),
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

                    // Scrollable Days & Events Grid
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _horizontalController,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: List.generate(_totalDays, (index) {
                            final day = _baseSunday.add(Duration(days: index));
                            final isSelected = day.year == widget.anchorDate.year &&
                                day.month == widget.anchorDate.month &&
                                day.day == widget.anchorDate.day;

                            final dayEvents = allEvents.where((e) {
                              final start = e.startTime.toLocal();
                              return start.year == day.year &&
                                  start.month == day.month &&
                                  start.day == day.day;
                            }).toList();

                            return _buildDayColumn(context, day, dayEvents, isSelected, isDark);
                          }),
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

  Widget _buildDaysHeader(BuildContext context, bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF131B2E) : const Color(0xFFF1F5F9),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: _timeGutterWidth,
            child: const Center(
              child: Icon(Icons.access_time, size: 16, color: Colors.grey),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: ScrollController(), // passive mirror
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_totalDays, (index) {
                  final day = _baseSunday.add(Duration(days: index));
                  final isToday = _isSameDay(day, DateTime.now());
                  final isSelected = _isSameDay(day, widget.anchorDate);

                  return InkWell(
                    onTap: () => widget.onDateSelected(day),
                    child: Container(
                      width: _dayColumnWidth,
                      padding: const EdgeInsets.symmetric(vertical: 4),
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
                            ? Theme.of(context).colorScheme.primary.withOpacity(isDark ? 0.2 : 0.1)
                            : Colors.transparent,
                      ),
                      child: Column(
                        children: [
                          Text(
                            DateFormat('EEE').format(day), // Sun, Mon, Tue...
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: day.weekday == 7
                                  ? Colors.redAccent
                                  : (isToday ? Theme.of(context).colorScheme.primary : Colors.grey),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            padding: const EdgeInsets.all(5),
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
                }),
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
  ) {
    final totalHeight = (_endHour - _startHour + 1) * _hourHeight;

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

          // Empty slot tap detector (quick add event at that hour)
          ...List.generate(_endHour - _startHour + 1, (index) {
            final hour = _startHour + index;
            return Positioned(
              top: index * _hourHeight,
              left: 0,
              right: 0,
              height: _hourHeight,
              child: InkWell(
                onTap: () {
                  final initialStart = DateTime(day.year, day.month, day.day, hour, 0);
                  AddEventDialog.show(context, initialDate: initialStart);
                },
                child: const SizedBox.expand(),
              ),
            );
          }),

          // Events positioned by time
          ...events.map((event) {
            return _buildEventTile(context, event, isDark);
          }),
        ],
      ),
    );
  }

  Widget _buildEventTile(BuildContext context, Event event, bool isDark) {
    final start = event.startTime.toLocal();
    final end = event.endTime.toLocal();

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
        onTap: () => _showEventDetails(context, event),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            // Solid color for fixed schedules/deadlines; Translucent color for auto-scheduled events
            color: isAuto
                ? baseColor.withOpacity(isDark ? 0.25 : 0.18)
                : baseColor,
            borderRadius: BorderRadius.circular(8),
            border: isAuto
                ? Border.all(color: baseColor, width: 1.5)
                : Border.all(color: Colors.white24, width: 0.5),
            boxShadow: isAuto
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
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
                      child: Icon(Icons.flash_on, size: 12, color: Colors.purpleAccent),
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
              if (height >= 40)
                Text(
                  '${DateFormat('h:mm a').format(start)} – ${DateFormat('h:mm a').format(end)}',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: isAuto
                        ? (isDark ? Colors.white70 : Colors.black54)
                        : Colors.white.withOpacity(0.9),
                  ),
                  maxLines: 1,
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEventDetails(BuildContext context, Event event) {
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
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: () async {
                    await ref.read(eventDaoProvider).deleteEvent(event.id);
                    Navigator.of(sheetContext).pop();
                    setState(() {});
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${DateFormat('EEEE, MMMM d, yyyy').format(event.startTime.toLocal())}\n'
              '${DateFormat('h:mm a').format(event.startTime.toLocal())} – ${DateFormat('h:mm a').format(event.endTime.toLocal())}',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            if (event.isAutoScheduled)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 16, color: Colors.purpleAccent),
                    SizedBox(width: 6),
                    Text(
                      'Auto-Scheduled Preparation / Habit Session',
                      style: TextStyle(fontSize: 12, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
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
      'commute' || 'transportation' => const Color(0xFFE74C3C),
      _ => const Color(0xFF3B82F6),
    };
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

