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
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/screens/calendar/widgets/timetable_view.dart';
import 'package:kairos/ui/widgets/add_event_dialog.dart';
import 'package:kairos/ui/widgets/app_global_actions.dart';
import 'package:kairos/ui/widgets/category_badge.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _currentWeekStart;
  String? _selectedCategoryFilter;

  @override
  void initState() {
    super.initState();
    _currentWeekStart = _getSundayStart(DateTime.now());
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
    final isTimetable = settings.calendarViewMode == 'timetable';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          DateFormat('MMMM yyyy').format(selectedDate),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          // Jump to Date button
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
          // Toggle between Timetable and List view
          IconButton(
            icon: Icon(isTimetable ? Icons.view_agenda_outlined : Icons.calendar_view_week),
            tooltip: isTimetable ? 'Switch to List View' : 'Switch to Timetable View',
            onPressed: () {
              ref
                  .read(settingsNotifierProvider.notifier)
                  .setCalendarViewMode(isTimetable ? 'list' : 'timetable');
            },
          ),
          // Global actions (Scheduler, theme, add task, add event, guide, settings)
          const AppGlobalActions(showAddButtons: false),
        ],
      ),
      body: isTimetable
          ? TimetableView(
              anchorDate: selectedDate,
              onDateSelected: (day) {
                setState(() {
                  _currentWeekStart = _getSundayStart(day);
                });
                ref.read(selectedDateProvider.notifier).state = day;
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
                      final filtered = _selectedCategoryFilter == null
                          ? events
                          : events
                              .where((e) =>
                                  e.category.toLowerCase() ==
                                  _selectedCategoryFilter!.toLowerCase())
                              .toList();

                      if (filtered.isEmpty) {
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

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final event = filtered[index];
                          return _buildEventCard(event);
                        },
                      );
                    },
                  ),
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
                        : (isToday ? Colors.blue.withOpacity(0.12) : Colors.transparent),
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

  Widget _buildEventCard(Event event) {
    final start = event.startTime.toLocal();
    final end = event.endTime.toLocal();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: event.isAutoScheduled
            ? const CircleAvatar(
                backgroundColor: Colors.purpleAccent,
                child: Icon(Icons.flash_on, color: Colors.white, size: 20),
              )
            : CircleAvatar(
                backgroundColor: _getCategoryColor(event.category),
                child: Text(
                  event.title.isNotEmpty ? event.title[0].toUpperCase() : 'E',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
              '${DateFormat('h:mm a').format(start)} – ${DateFormat('h:mm a').format(end)}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                CategoryBadge(categorySlugOrName: event.category, compact: true),
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
                  Text('${event.prepMinutes ?? 60}m prep', style: const TextStyle(fontSize: 11, color: Colors.purpleAccent)),
                ],
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
          onPressed: () async {
            await ref.read(eventDaoProvider).deleteEvent(event.id);
            ref.invalidate(selectedDateEventsProvider);
            ref.invalidate(todayEventsProvider);
          },
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
}
