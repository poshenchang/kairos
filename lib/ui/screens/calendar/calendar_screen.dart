// lib/ui/screens/calendar/calendar_screen.dart
//
// Calendar screen with:
// - Default Timetable View (schedule grid) and alternate List View
// - Week starting on Sunday
// - Horizontal scroll into future dates and manual date jump
// - Consistent top-right AppGlobalActions

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/supabase_sync_service.dart';
import 'package:kairos/services/timezone_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/screens/calendar/widgets/timetable_view.dart';
import 'package:kairos/ui/screens/calendar/widgets/all_events_view.dart';
import 'package:kairos/ui/screens/calendar/widgets/schedule_sidebar.dart';
import 'package:kairos/ui/widgets/add_event_dialog.dart';
import 'package:kairos/ui/widgets/edit_event_dialog.dart';
import 'package:kairos/ui/widgets/app_global_actions.dart';
import 'package:kairos/ui/widgets/category_badge.dart';
import 'package:kairos/ui/widgets/undo_snackbar.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _currentWeekStart;
  String? _selectedCategoryFilter;
  bool _showSidebar = true;
  DateTime _displayedTimetableMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _currentWeekStart = _getSundayStart(DateTime.now());
    _displayedTimetableMonth = DateTime.now();
  }

  DateTime _getSundayStart(DateTime date) {
    // Week starts on Sunday! Sunday in Dart is weekday 7 (7 % 7 = 0)
    final daysBack = date.weekday % 7;
    final d = date.subtract(Duration(days: daysBack));
    return DateTime(d.year, d.month, d.day);
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final eventsAsync = ref.watch(selectedDateEventsProvider);
    final categoriesAsync = ref.watch(allCategoriesProvider);
    final categories = categoriesAsync.value ?? [];
    final settings = ref.watch(settingsNotifierProvider);
    final viewMode = settings.calendarViewMode;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          viewMode == 'all'
              ? (isMobile ? 'All Events' : 'All Events Directory')
              : (isMobile
                  ? DateFormat('MMMM').format(viewMode == 'timetable' ? _displayedTimetableMonth : selectedDate)
                  : DateFormat('MMMM yyyy').format(viewMode == 'timetable' ? _displayedTimetableMonth : selectedDate)),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          // Sidebar Toggle button for Timetable mode
          if (viewMode == 'timetable')
            IconButton(
              icon: Icon(_showSidebar ? Icons.view_sidebar : Icons.view_sidebar_outlined),
              tooltip: _showSidebar ? 'Hide Schedule Assistant' : 'Show Schedule Assistant',
              onPressed: () => setState(() => _showSidebar = !_showSidebar),
            ),
          // Jump to Date button
          if (viewMode != 'all')
            IconButton(
              icon: const Icon(Icons.calendar_month),
              tooltip: 'Jump to Date',
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                );
                if (picked != null) {
                  setState(() {
                    _currentWeekStart = _getSundayStart(picked);
                  });
                  ref.read(selectedDateProvider.notifier).state = picked;
                }
              },
            ),
          // Global actions (Scheduler, theme, add task, add event, guide, settings)
          const AppGlobalActions(showAddButtons: false),
        ],
      ),
      body: Column(
        children: [
          // View Switcher Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'timetable',
                    icon: Icon(Icons.calendar_view_week, size: 16),
                    label: Text('Timetable'),
                  ),
                  ButtonSegment(
                    value: 'list',
                    icon: Icon(Icons.view_agenda, size: 16),
                    label: Text('Agenda'),
                  ),
                  ButtonSegment(
                    value: 'all',
                    icon: Icon(Icons.category, size: 16),
                    label: Text('All Events'),
                  ),
                ],
                selected: {viewMode == 'all' ? 'all' : (viewMode == 'list' ? 'list' : 'timetable')},
                onSelectionChanged: (val) {
                  ref
                      .read(settingsNotifierProvider.notifier)
                      .setCalendarViewMode(val.first);
                },
              ),
            ),
          ),
          const Divider(height: 1),
          // Body View Content
          Expanded(
            child: viewMode == 'all'
                ? const AllEventsView()
                : (viewMode == 'timetable'
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          final isCompact = constraints.maxWidth < 720;
                          final timetable = TimetableView(
                            anchorDate: selectedDate,
                            onDateSelected: (day) {
                              setState(() {
                                _currentWeekStart = _getSundayStart(day);
                              });
                              ref.read(selectedDateProvider.notifier).state = day;
                            },
                            onVisibleMonthChanged: (m) {
                              if (_displayedTimetableMonth.year != m.year ||
                                  _displayedTimetableMonth.month != m.month) {
                                setState(() => _displayedTimetableMonth = m);
                              }
                            },
                          );

                          if (isCompact) {
                            return Column(
                              children: [
                                Expanded(child: timetable),
                                if (_showSidebar) ...[
                                  const Divider(height: 1, thickness: 1),
                                  SizedBox(
                                    height: 220,
                                    child: ScheduleSidebar(
                                      currentWeekStart: _currentWeekStart,
                                      isHorizontal: true,
                                      onClose: () => setState(() => _showSidebar = false),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          } else {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expanded(child: timetable),
                                if (_showSidebar) ...[
                                  const VerticalDivider(width: 1, thickness: 1),
                                  SizedBox(
                                    width: 310,
                                    child: ScheduleSidebar(
                                      currentWeekStart: _currentWeekStart,
                                      isHorizontal: false,
                                      onClose: () => setState(() => _showSidebar = false),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          }
                        },
                      )
                    : Column(
                        children: [
                          // 1. Week Navigation & Day Selector Strip (Starts on Sunday)
                          _buildWeekStrip(selectedDate),

                          // 2. Category Filter Chips
                          _buildCategoryFilters(categories),

                          const Divider(height: 1),

                          // 3. Day Events List
                          Expanded(
                            child: eventsAsync.when(
                              loading: () => const Center(child: CircularProgressIndicator()),
                              error: (err, _) => Center(child: Text('Error: $err')),
                              data: (events) {
                                final holidaysAsync = ref.watch(holidaysForDateProvider(selectedDate));
                                final dayHolidays = holidaysAsync.value ?? [];

                                final filtered = (_selectedCategoryFilter == null
                                    ? List<Event>.from(events)
                                    : events
                                        .where((e) =>
                                            e.category.toLowerCase() ==
                                            _selectedCategoryFilter!.toLowerCase())
                                        .toList())
                                  ..sort((a, b) {
                                    // Hard events (!isAutoScheduled) first, soft (isAutoScheduled) later
                                    if (!a.isAutoScheduled && b.isAutoScheduled) return -1;
                                    if (a.isAutoScheduled && !b.isAutoScheduled) return 1;
                                    return a.startTime.compareTo(b.startTime);
                                  });

                                if (filtered.isEmpty && dayHolidays.isEmpty) {
                                  return Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.event_available, size: 48, color: Colors.grey),
                                        const SizedBox(height: 12),
                                        Text(
                                          'No events on ${DateFormat('EEE, MMM d').format(selectedDate)}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        const SizedBox(height: 6),
                                        const Text(
                                          'Tap + below to add classes, gym sessions, or meetings.',
                                          style: TextStyle(color: Colors.grey, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                final totalCount = dayHolidays.length +
                                    filtered.length +
                                    (filtered.isEmpty && dayHolidays.isNotEmpty ? 1 : 0);

                                return ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  itemCount: totalCount,
                                  itemBuilder: (context, index) {
                                    if (index < dayHolidays.length) {
                                      return _buildHolidayCard(dayHolidays[index]);
                                    }
                                    if (filtered.isEmpty) {
                                      return const Padding(
                                        padding: EdgeInsets.symmetric(vertical: 24),
                                        child: Center(
                                          child: Text(
                                            'No other scheduled events on this holiday.',
                                            style: TextStyle(color: Colors.grey, fontSize: 13),
                                          ),
                                        ),
                                      );
                                    }
                                    final eventIndex = index - dayHolidays.length;
                                    final event = filtered[eventIndex];
                                    return _buildEventCard(event, categories);
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      )),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AddEventDialog.show(context, initialDate: selectedDate),
        icon: const Icon(Icons.add),
        label: const Text('Add Event'),
      ),
    );
  }

  Widget _buildWeekStrip(DateTime selectedDate) {
    // 7 days starting from Sunday
    final weekDays = List.generate(7, (i) => _currentWeekStart.add(Duration(days: i)));
    const dayHeaders = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() {
                    _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7));
                  });
                },
              ),
              Text(
                '${DateFormat('MMM d').format(_currentWeekStart)} – ${DateFormat('MMM d').format(_currentWeekStart.add(const Duration(days: 6)))}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() {
                    _currentWeekStart = _currentWeekStart.add(const Duration(days: 7));
                  });
                },
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(7, (index) {
              final day = weekDays[index];
              final isSelected = day.year == selectedDate.year &&
                  day.month == selectedDate.month &&
                  day.day == selectedDate.day;
              final isToday = day.year == DateTime.now().year &&
                  day.month == DateTime.now().month &&
                  day.day == DateTime.now().day;

              return InkWell(
                onTap: () {
                  ref.read(selectedDateProvider.notifier).state = day;
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : (isToday ? Colors.blue.withValues(alpha: 0.12) : Colors.transparent),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        dayHeaders[index],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isSelected
                              ? Colors.white
                              : (index == 0 ? Colors.redAccent : Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? Colors.white
                              : (isToday
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).textTheme.bodyMedium?.color),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilters(List<Category> categories) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('All Events'),
            selected: _selectedCategoryFilter == null,
            onSelected: (_) => setState(() => _selectedCategoryFilter = null),
          ),
          const SizedBox(width: 6),
          ...categories.map((c) {
            return Padding(
              padding: const EdgeInsets.only(right: 6.0),
              child: ChoiceChip(
                label: Text('${c.emoji} ${c.name}'),
                selected: _selectedCategoryFilter == c.slug,
                onSelected: (val) {
                  setState(() => _selectedCategoryFilter = val ? c.slug : null);
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatHolidayCategory(String groupName) {
    final lower = groupName.toLowerCase();
    if (lower.endsWith('holidays')) {
      return groupName.substring(0, groupName.length - 1);
    }
    if (lower.endsWith('breaks')) {
      return groupName.substring(0, groupName.length - 1);
    }
    return groupName;
  }

  Widget _buildHolidayCard(Holiday h) {
    final catName = _formatHolidayCategory(h.groupName);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.redAccent.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.25)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.redAccent.withValues(alpha: 0.15),
          child: const Icon(Icons.celebration, color: Colors.redAccent, size: 20),
        ),
        title: Text(
          '$catName: ${h.name}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            const Text(
              'All-day • Holiday',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.beach_access, size: 10, color: Colors.redAccent),
                      SizedBox(width: 4),
                      Text(
                        'All-Day Holiday',
                        style: TextStyle(fontSize: 10, color: Colors.redAccent, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEventCard(Event event, List<Category> categories) {
    final settings = ref.watch(settingsNotifierProvider);
    final start = TimezoneService.instance.toActiveTime(event.startTime, settings);
    final end = TimezoneService.instance.toActiveTime(event.endTime, settings);
    final isReminder = event.eventType == 'reminder';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isReminder
              ? Colors.amber.withValues(alpha: 0.15)
              : _getCategoryColor(event.category).withValues(alpha: 0.15),
          child: isReminder
              ? const Icon(Icons.notifications_active, color: Colors.amber, size: 20)
              : Text(
                  _getCategoryEmoji(event.category, categories),
                  style: const TextStyle(fontSize: 18),
                ),
        ),
        title: Text(
          event.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              isReminder
                  ? 'Reminder at ${DateFormat('h:mm a').format(start)}'
                  : '${DateFormat('h:mm a').format(start)} – ${DateFormat('h:mm a').format(end)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                CategoryBadge(categorySlugOrName: event.category, compact: true),
                if (isReminder) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications, size: 10, color: Colors.amber),
                        SizedBox(width: 3),
                        Text('Reminder', style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
                if (event.isAutoScheduled) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.purple.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, size: 10, color: Colors.purple),
                        SizedBox(width: 3),
                        Text('Scheduled', style: TextStyle(fontSize: 10, color: Colors.purple, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ],
                if (event.isRecurring) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.repeat, size: 12, color: Colors.grey),
                  const SizedBox(width: 2),
                  const Text('Weekly', style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
                if (event.requiresPrep) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.auto_awesome, size: 12, color: Colors.purpleAccent),
                  const SizedBox(width: 2),
                  Text(
                    (event.prepMinutes ?? 60) >= 60 && (event.prepMinutes ?? 60) % 60 == 0
                        ? '${(event.prepMinutes ?? 60) ~/ 60}h prep'
                        : '${event.prepMinutes ?? 60}m prep',
                    style: const TextStyle(fontSize: 11, color: Colors.purpleAccent),
                  ),
                ],
              ],
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blueGrey),
              tooltip: 'Edit Event',
              onPressed: () => EditEventDialog.show(context, event, occurrenceDate: event.startTime),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
              tooltip: 'Delete Event',
              onPressed: () async {
                final container = ProviderScope.containerOf(context);
                final dao = ref.read(eventDaoProvider);
                void pushToCloud() {
                  container.read(supabaseSyncServiceProvider.notifier).syncNow();
                }

                showUndoSnackBar(
                  context,
                  message: 'Deleted "${event.title}"',
                  onUndo: () async {
                    await dao.restoreEvent(event.id);
                    pushToCloud();
                  },
                );
                await dao.deleteEvent(event.id);
                pushToCloud();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _getCategoryEmoji(String categorySlugOrName, List<Category> categories) {
    for (final c in categories) {
      if (c.slug.toLowerCase() == categorySlugOrName.toLowerCase() ||
          c.name.toLowerCase() == categorySlugOrName.toLowerCase()) {
        if (c.emoji.isNotEmpty) return c.emoji;
      }
    }
    return switch (categorySlugOrName.toLowerCase()) {
      'schoolwork' => '🎓',
      'work' => '💼',
      'research' => '🔬',
      'personal' => '🧘',
      'social' => '🎉',
      'commute' || 'transportation' => '🚆',
      _ => '🌐',
    };
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
}
