// lib/ui/screens/calendar/widgets/schedule_sidebar.dart
//
// Sidebar panel on the calendar screen displaying:
// - Active habits with weekly completions & scheduled counts
// - Exam & Interview preparation sessions
// - Uncompleted tasks with scheduled time vs suggested session duration
// - Subtasks that can be dragged individually onto the timetable grid
// - Drag-and-drop handles for semi-manual scheduling
// - Habit default schedule setup & one-click week initialization

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/event_repository.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/habit_schedule_service.dart';
import 'package:kairos/services/notification_service.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/timezone_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/screens/calendar/widgets/drag_schedule_item.dart';
import 'package:kairos/ui/widgets/add_event_dialog.dart';
import 'package:kairos/ui/widgets/habit_schedule_dialog.dart';
import 'package:kairos/ui/widgets/task_form_sheet.dart';
import 'package:kairos/ui/widgets/habit_form_sheet.dart';

class ScheduleSidebar extends ConsumerStatefulWidget {
  final DateTime currentWeekStart;
  final bool isHorizontal;
  final VoidCallback? onClose;

  const ScheduleSidebar({
    super.key,
    required this.currentWeekStart,
    this.isHorizontal = false,
    this.onClose,
  });

  @override
  ConsumerState<ScheduleSidebar> createState() => _ScheduleSidebarState();
}

class _SidebarItem {
  final int typePriority; // 0: Task, 1: Prep, 2: Habit
  final bool isScheduled; // false: unscheduled, true: scheduled
  final DateTime sortDate; // urgency / date
  final Widget cardWidget;

  _SidebarItem({
    required this.typePriority,
    required this.isScheduled,
    required this.sortDate,
    required this.cardWidget,
  });
}

class _ScheduleSidebarState extends ConsumerState<ScheduleSidebar> {
  String _selectedTab = 'all'; // 'all', 'tasks', 'preps', 'habits'

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final tasksAsync = ref.watch(incompleteTasksStreamProvider);
    final habitsAsync = ref.watch(activeHabitsProvider);
    final completionsAsync = ref.watch(habitCompletionsForWeekProvider(widget.currentWeekStart));
    final allEventsAsync = ref.watch(allEventsStreamProvider);
    final habitSchedules = ref.watch(habitScheduleProvider);
    final eventRepo = ref.watch(eventRepositoryProvider);

    final tasks = tasksAsync.value ?? [];
    final habits = habitsAsync.value ?? [];
    final completions = completionsAsync.value ?? {};
    final allEvents = allEventsAsync.value ?? [];

    final settings = ref.watch(settingsNotifierProvider);

    // Filter upcoming events that require preparation (Exams, Interviews, Presentations)
    // Supports both single events and recurring event series.
    final now = TimezoneService.instance.activeNow(settings);
    final prepEvents = <Event>[];
    for (final e in allEvents) {
      if (e.isDeleted || !e.requiresPrep || e.isAutoScheduled) continue;
      if (e.isRecurring && e.rrule != null && e.rrule!.isNotEmpty) {
        final occurrences = eventRepo.expandRecurringEvents(
          e,
          now.subtract(const Duration(days: 7)),
          now.add(const Duration(days: 60)),
          settings: settings,
        );
        final hasUpcoming = occurrences.any((occ) {
          final activeEnd = TimezoneService.instance.toActiveTime(occ.endTime, settings);
          return activeEnd.isAfter(now);
        });
        if (hasUpcoming) {
          prepEvents.add(e);
        }
      } else {
        final activeEnd = TimezoneService.instance.toActiveTime(e.endTime, settings);
        if (activeEnd.isAfter(now)) {
          prepEvents.add(e);
        }
      }
    }
    prepEvents.sort((a, b) => a.startTime.compareTo(b.startTime));

    final totalCount = tasks.length + habits.length + prepEvents.length;

    return Container(
      color: isDark ? const Color(0xFF131A2A) : const Color(0xFFF8FAFC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.isHorizontal) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.drag_indicator,
                    color: theme.colorScheme.primary,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Schedule Assistant',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const Spacer(),
                  if (habits.isNotEmpty)
                    TextButton.icon(
                      icon: const Icon(Icons.auto_awesome, size: 14, color: Colors.purpleAccent),
                      label: const Text('Init Week', style: TextStyle(fontSize: 11, color: Colors.purpleAccent)),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      ),
                      onPressed: () => _populateWeekHabits(context, ref, habits, allEvents, isDark),
                    ),
                  if (widget.onClose != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Close Assistant',
                      onPressed: widget.onClose,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: [
                    ButtonSegment(
                      value: 'all',
                      label: Text('All ($totalCount)', style: const TextStyle(fontSize: 10)),
                    ),
                    ButtonSegment(
                      value: 'tasks',
                      label: Text('Tasks (${tasks.length})', style: const TextStyle(fontSize: 10)),
                    ),
                    ButtonSegment(
                      value: 'preps',
                      label: Text('Preps (${prepEvents.length})', style: const TextStyle(fontSize: 10)),
                    ),
                    ButtonSegment(
                      value: 'habits',
                      label: Text('Habits (${habits.length})', style: const TextStyle(fontSize: 10)),
                    ),
                  ],
                  selected: {_selectedTab},
                  onSelectionChanged: (val) {
                    setState(() => _selectedTab = val.first);
                  },
                ),
              ),
            ),
            const Divider(height: 6),
            Expanded(
              child: _buildHorizontalContent(
                context,
                habits: habits,
                completions: completions,
                prepEvents: prepEvents,
                tasks: tasks,
                allEvents: allEvents,
                habitSchedules: habitSchedules,
                isDark: isDark,
                now: now,
                settings: settings,
                eventRepo: eventRepo,
              ),
            ),
          ] else ...[
            // Sidebar Header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.drag_indicator,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Schedule Assistant',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          'Drag into timetable slots',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.onClose != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Close Sidebar',
                      onPressed: widget.onClose,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ),

            // Filter Segmented Control (Order: All, Tasks, Preps, Habits)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
              child: SizedBox(
                height: 32,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  segments: [
                    ButtonSegment(
                      value: 'all',
                      label: Text('All ($totalCount)', style: const TextStyle(fontSize: 10.5)),
                    ),
                    ButtonSegment(
                      value: 'tasks',
                      label: Text('Tasks (${tasks.length})', style: const TextStyle(fontSize: 10.5)),
                    ),
                    ButtonSegment(
                      value: 'preps',
                      label: Text('Preps (${prepEvents.length})', style: const TextStyle(fontSize: 10.5)),
                    ),
                    ButtonSegment(
                      value: 'habits',
                      label: Text('Habits (${habits.length})', style: const TextStyle(fontSize: 10.5)),
                    ),
                  ],
                  selected: {_selectedTab},
                  onSelectionChanged: (val) {
                    setState(() => _selectedTab = val.first);
                  },
                ),
              ),
            ),
            const Divider(height: 12),

            // Content List
            Expanded(
              child: Builder(
                builder: (context) {
                  final weekStart = DateTime(widget.currentWeekStart.year, widget.currentWeekStart.month, widget.currentWeekStart.day);
                  final weekEnd = weekStart.add(const Duration(days: 7));
                  final items = <_SidebarItem>[];

                  // 1. Tasks (typePriority: 0)
                  if (_selectedTab == 'all' || _selectedTab == 'tasks') {
                    for (final task in tasks) {
                      final isSched = _isTaskScheduled(task, allEvents);
                      items.add(_SidebarItem(
                        typePriority: 0,
                        isScheduled: isSched,
                        sortDate: task.dueDate,
                        cardWidget: _buildTaskCard(context, task, allEvents, isDark),
                      ));
                    }
                  }

                  // 2. Preps (typePriority: 1)
                  if (_selectedTab == 'all' || _selectedTab == 'preps') {
                    for (final event in prepEvents) {
                      final isSched = _isPrepScheduled(event, allEvents, now, settings, eventRepo);
                      final sortDate = _getUpcomingPrepStart(event, now, settings, eventRepo);
                      items.add(_SidebarItem(
                        typePriority: 1,
                        isScheduled: isSched,
                        sortDate: sortDate,
                        cardWidget: _buildPrepCard(context, event, allEvents, isDark, now, settings, eventRepo),
                      ));
                    }
                  }

                  // 3. Habits (typePriority: 2)
                  if (_selectedTab == 'all' || _selectedTab == 'habits') {
                    for (final habit in habits) {
                      final completedCount = completions[habit.id] ?? 0;
                      final isSched = _isHabitScheduled(habit, completedCount, allEvents, weekStart, weekEnd, settings);
                      items.add(_SidebarItem(
                        typePriority: 2,
                        isScheduled: isSched,
                        sortDate: DateTime(2099, 1, 1),
                        cardWidget: _buildHabitCard(
                          context,
                          habit,
                          completions,
                          allEvents,
                          habitSchedules[habit.id] ?? [],
                          isDark,
                        ),
                      ));
                    }
                  }

                  // Sorting:
                  // Rule 1 (Highest priority): Unscheduled items first (!isScheduled)
                  // Rule 2: Tasks (0) -> Prep (1) -> Habits (2)
                  // Rule 3: Date / Urgency
                  items.sort((a, b) {
                    if (!a.isScheduled && b.isScheduled) return -1;
                    if (a.isScheduled && !b.isScheduled) return 1;
                    if (a.typePriority != b.typePriority) {
                      return a.typePriority.compareTo(b.typePriority);
                    }
                    return a.sortDate.compareTo(b.sortDate);
                  });

                  if (_selectedTab == 'all') {
                    final unscheduled = items.where((i) => !i.isScheduled).toList();
                    final scheduled = items.where((i) => i.isScheduled).toList();

                    return ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      children: [
                        if (unscheduled.isNotEmpty) ...[
                          _buildSectionHeader(
                            context,
                            title: 'To Schedule (Needs Time)',
                            icon: Icons.pending_actions,
                            count: unscheduled.length,
                          ),
                          if (habits.isNotEmpty && unscheduled.any((i) => i.typePriority == 2))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0, top: 2.0),
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.auto_awesome, size: 14, color: Colors.purpleAccent),
                                label: const Text('Initialize Week with Default Habits', style: TextStyle(fontSize: 11)),
                                style: OutlinedButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  side: BorderSide(color: Colors.purple.withValues(alpha: 0.4)),
                                ),
                                onPressed: () => _populateWeekHabits(context, ref, habits, allEvents, isDark),
                              ),
                            ),
                          ...unscheduled.map((i) => i.cardWidget),
                          const SizedBox(height: 14),
                        ],
                        if (scheduled.isNotEmpty) ...[
                          _buildSectionHeader(
                            context,
                            title: 'Scheduled & Fulfilled',
                            icon: Icons.task_alt,
                            count: scheduled.length,
                          ),
                          ...scheduled.map((i) => i.cardWidget),
                        ],
                        if (unscheduled.isEmpty && scheduled.isEmpty)
                          _buildEmptyState('No items to schedule', 'Add tasks, prep events, or habits to get started'),
                      ],
                    );
                  }

                  if (_selectedTab == 'tasks') {
                    final taskItems = items.where((i) => i.typePriority == 0).toList();
                    return ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      children: [
                        _buildSectionHeader(
                          context,
                          title: 'Tasks & Deadlines',
                          icon: Icons.check_circle_outline,
                          count: tasks.length,
                          onAdd: () => TaskFormSheet.show(context),
                        ),
                        if (taskItems.isEmpty)
                          _buildEmptyState('All tasks caught up!', 'Add a new deadline to get started')
                        else
                          ...taskItems.map((i) => i.cardWidget),
                      ],
                    );
                  }

                  if (_selectedTab == 'preps') {
                    final prepItems = items.where((i) => i.typePriority == 1).toList();
                    return ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      children: [
                        _buildSectionHeader(
                          context,
                          title: 'Exam & Interview Preps',
                          icon: Icons.school_outlined,
                          count: prepEvents.length,
                          onAdd: () => AddEventDialog.show(context),
                        ),
                        if (prepItems.isEmpty)
                          _buildEmptyState('No exam/interview preps needed', 'Create an event with "Requires Prep" enabled')
                        else
                          ...prepItems.map((i) => i.cardWidget),
                      ],
                    );
                  }

                  // _selectedTab == 'habits'
                  final habitItems = items.where((i) => i.typePriority == 2).toList();
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    children: [
                      _buildSectionHeader(
                        context,
                        title: 'Active Habits',
                        icon: Icons.repeat,
                        count: habits.length,
                        onAdd: () => HabitFormSheet.show(context),
                      ),
                      if (habits.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0, top: 2.0),
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.auto_awesome, size: 14, color: Colors.purpleAccent),
                            label: const Text('Initialize Week with Default Habits', style: TextStyle(fontSize: 11)),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              side: BorderSide(color: Colors.purple.withValues(alpha: 0.4)),
                            ),
                            onPressed: () => _populateWeekHabits(context, ref, habits, allEvents, isDark),
                          ),
                        ),
                      if (habitItems.isEmpty)
                        _buildEmptyState('No active habits', 'Create one to schedule regular practice')
                      else
                        ...habitItems.map((i) => i.cardWidget),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHorizontalContent(
    BuildContext context, {
    required List<Habit> habits,
    required Map<int, int> completions,
    required List<Event> prepEvents,
    required List<Task> tasks,
    required List<Event> allEvents,
    required Map<int, List<HabitDefaultSlot>> habitSchedules,
    required bool isDark,
    required DateTime now,
    required SettingsState settings,
    required EventRepository eventRepo,
  }) {
    final items = <_SidebarItem>[];
    final weekStart = DateTime(widget.currentWeekStart.year, widget.currentWeekStart.month, widget.currentWeekStart.day);
    final weekEnd = weekStart.add(const Duration(days: 7));

    // Tasks (typePriority: 0)
    if (_selectedTab == 'all' || _selectedTab == 'tasks') {
      for (final task in tasks) {
        final isSched = _isTaskScheduled(task, allEvents);
        items.add(_SidebarItem(
          typePriority: 0,
          isScheduled: isSched,
          sortDate: task.dueDate,
          cardWidget: _buildTaskCard(context, task, allEvents, isDark),
        ));
      }
    }

    // Preps (typePriority: 1)
    if (_selectedTab == 'all' || _selectedTab == 'preps') {
      for (final event in prepEvents) {
        final isSched = _isPrepScheduled(event, allEvents, now, settings, eventRepo);
        final sortDate = _getUpcomingPrepStart(event, now, settings, eventRepo);
        items.add(_SidebarItem(
          typePriority: 1,
          isScheduled: isSched,
          sortDate: sortDate,
          cardWidget: _buildPrepCard(context, event, allEvents, isDark, now, settings, eventRepo),
        ));
      }
    }

    // Habits (typePriority: 2)
    if (_selectedTab == 'all' || _selectedTab == 'habits') {
      for (final habit in habits) {
        final completedCount = completions[habit.id] ?? 0;
        final isSched = _isHabitScheduled(habit, completedCount, allEvents, weekStart, weekEnd, settings);
        items.add(_SidebarItem(
          typePriority: 2,
          isScheduled: isSched,
          sortDate: DateTime(2099, 1, 1),
          cardWidget: _buildHabitCard(
            context,
            habit,
            completions,
            allEvents,
            habitSchedules[habit.id] ?? [],
            isDark,
          ),
        ));
      }
    }

    // Sorting:
    // Rule 1 (Highest priority): Unscheduled items first (!isScheduled)
    // Rule 2: Tasks (0) -> Prep (1) -> Habits (2)
    // Rule 3: Date / Urgency
    items.sort((a, b) {
      if (!a.isScheduled && b.isScheduled) return -1;
      if (a.isScheduled && !b.isScheduled) return 1;
      if (a.typePriority != b.typePriority) {
        return a.typePriority.compareTo(b.typePriority);
      }
      return a.sortDate.compareTo(b.sortDate);
    });

    final cardWidgets = <Widget>[];

    // Prepend Init Week card for habits when habits are shown
    if ((_selectedTab == 'all' || _selectedTab == 'habits') && habits.isNotEmpty) {
      cardWidgets.add(_buildInitWeekCard(context, ref, habits, allEvents, isDark));
    }

    for (final item in items) {
      cardWidgets.add(
        SizedBox(
          width: 260,
          child: SingleChildScrollView(
            child: item.cardWidget,
          ),
        ),
      );
    }

    if (cardWidgets.isEmpty) {
      return Center(
        child: Text(
          _selectedTab == 'habits'
              ? 'No active habits'
              : (_selectedTab == 'preps'
                  ? 'No exam/interview preps needed'
                  : (_selectedTab == 'tasks' ? 'All tasks caught up!' : 'No scheduled items available')),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      );
    }

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      itemCount: cardWidgets.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, index) => cardWidgets[index],
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required IconData icon,
    required int count,
    VoidCallback? onAdd,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, top: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const Spacer(),
          if (onAdd != null)
            IconButton(
              icon: const Icon(Icons.add, size: 16),
              tooltip: 'Add $title',
              onPressed: onAdd,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
      child: Center(
        child: Column(
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHabitCard(
    BuildContext context,
    Habit habit,
    Map<int, int> completions,
    List<Event> allEvents,
    List<HabitDefaultSlot> defaultSlots,
    bool isDark,
  ) {
    final weekStart = DateTime(widget.currentWeekStart.year, widget.currentWeekStart.month, widget.currentWeekStart.day);
    final weekEnd = weekStart.add(const Duration(days: 7));

    final settings = ref.watch(settingsNotifierProvider);

    // Scheduled events for this habit this week
    final habitWeekEvents = allEvents.where((e) {
      if (e.isDeleted) return false;
      final start = TimezoneService.instance.toActiveTime(e.startTime, settings);
      if (start.isBefore(weekStart) || !start.isBefore(weekEnd)) return false;

      final src = e.autoScheduleSource;
      final matchesSource = src != null && (
        src == 'habit:${habit.id}' ||
        src.startsWith('habit:${habit.id};') ||
        src.startsWith('habit:${habit.id}:')
      );
      final matchesTitle = e.title.trim().toLowerCase() == habit.title.trim().toLowerCase();

      return matchesSource || (matchesTitle && (e.isAutoScheduled || e.category == habit.category));
    }).toList();

    final scheduledCount = habitWeekEvents.length;
    final completedCount = completions[habit.id] ?? 0;
    final target = habit.targetFrequencyPerWeek;
    final duration = habit.minSessionMinutes;
    final categoryColor = _getCategoryColor(habit.category);

    final dragItem = DragScheduleItem(
      type: DragScheduleType.habit,
      title: habit.title,
      category: habit.category,
      durationMinutes: duration,
      habit: habit,
    );

    return Draggable<DragScheduleItem>(
      data: dragItem,
      feedback: _buildDragFeedback(
        context,
        title: habit.title,
        category: habit.category,
        durationMinutes: duration,
        icon: Icons.repeat,
        badgeText: 'Habit • ${_formatMinutes(duration)}',
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _buildHabitContainer(
          context,
          habit,
          completedCount,
          scheduledCount,
          target,
          duration,
          categoryColor,
          defaultSlots,
          habitWeekEvents,
          isDark,
        ),
      ),
      child: _buildHabitContainer(
        context,
        habit,
        completedCount,
        scheduledCount,
        target,
        duration,
        categoryColor,
        defaultSlots,
        habitWeekEvents,
        isDark,
      ),
    );
  }

  Widget _buildHabitContainer(
    BuildContext context,
    Habit habit,
    int completedCount,
    int scheduledCount,
    int target,
    int duration,
    Color categoryColor,
    List<HabitDefaultSlot> defaultSlots,
    List<Event> habitWeekEvents,
    bool isDark,
  ) {
    final progress = target > 0 ? ((completedCount + scheduledCount) / target).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: widget.isHorizontal ? const EdgeInsets.only(bottom: 2) : const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: categoryColor.withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: categoryColor,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  habit.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Default schedule button / slot count
              IconButton(
                icon: const Icon(Icons.settings_suggest_outlined, size: 16, color: Colors.blueAccent),
                tooltip: defaultSlots.isNotEmpty
                    ? 'Default Schedule (${defaultSlots.length} slots/wk)'
                    : 'Configure Default Weekly Schedule',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => HabitScheduleDialog.show(context, habit),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _formatMinutes(duration),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: categoryColor,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.drag_indicator, size: 16, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$completedCount completed • $scheduledCount scheduled / $target target',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (defaultSlots.isNotEmpty)
                Text(
                  '${defaultSlots.length} default slots',
                  style: const TextStyle(fontSize: 9.5, color: Colors.purpleAccent, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(categoryColor),
            ),
          ),
        ],
      ),
    );
  }

  DateTime _getUpcomingPrepStart(Event event, DateTime now, SettingsState settings, EventRepository repo) {
    if (!event.isRecurring || event.rrule == null || event.rrule!.isEmpty) {
      return event.startTime;
    }
    final occurrences = repo.expandRecurringEvents(
      event,
      now.subtract(const Duration(days: 7)),
      now.add(const Duration(days: 60)),
      settings: settings,
    );
    occurrences.sort((a, b) => a.startTime.compareTo(b.startTime));
    for (final occ in occurrences) {
      final activeEnd = TimezoneService.instance.toActiveTime(occ.endTime, settings);
      if (activeEnd.isAfter(now)) {
        return occ.startTime;
      }
    }
    return event.startTime;
  }

  int _calculateScheduledPrepMinutes(Event event, List<Event> allEvents, DateTime now, SettingsState settings, EventRepository repo) {
    DateTime? windowStart;
    DateTime? windowEnd;

    if (event.isRecurring && event.rrule != null && event.rrule!.isNotEmpty) {
      final occurrences = repo.expandRecurringEvents(
        event,
        now.subtract(const Duration(days: 14)),
        now.add(const Duration(days: 90)),
        settings: settings,
      );
      occurrences.sort((a, b) => a.startTime.compareTo(b.startTime));

      Event? nextOcc;
      Event? prevOcc;
      for (final occ in occurrences) {
        final activeEnd = TimezoneService.instance.toActiveTime(occ.endTime, settings);
        if (activeEnd.isAfter(now)) {
          nextOcc = occ;
          break;
        }
        prevOcc = occ;
      }

      if (nextOcc != null) {
        windowEnd = nextOcc.startTime;
        windowStart = prevOcc != null
            ? prevOcc.endTime
            : nextOcc.startTime.subtract(const Duration(days: 7));
      }
    }

    final matchingPrepEvents = allEvents.where((e) {
      if (e.isDeleted) return false;
      final src = e.autoScheduleSource;
      if (src != null) {
        if (src == 'event:${event.id}:prep' ||
            src.startsWith('event:${event.id}:') ||
            src.startsWith('event:${event.id};') ||
            src == 'prep:${event.id}' ||
            src.startsWith('prep:${event.id}:') ||
            src.startsWith('prep:${event.id};')) {
          return true;
        }
      }
      final expectedTitle = 'prep: ${event.title.trim().toLowerCase()}';
      if (e.title.trim().toLowerCase() == expectedTitle && e.isAutoScheduled) {
        return true;
      }
      return false;
    });

    int scheduledMinutes = 0;
    for (final e in matchingPrepEvents) {
      if (windowStart != null && e.startTime.isBefore(windowStart)) continue;
      if (windowEnd != null && e.startTime.isAfter(windowEnd)) continue;
      scheduledMinutes += e.endTime.difference(e.startTime).inMinutes;
    }
    return scheduledMinutes;
  }

  int _calculateScheduledTaskMinutes(Task task, List<Event> allEvents) {
    final taskEvents = allEvents.where((e) {
      if (e.isDeleted) return false;
      if (e.autoScheduleSource?.startsWith('task:${task.id}') != true) return false;
      if (task.completedAt != null && e.endTime.isBefore(task.completedAt!)) {
        return false;
      }
      return true;
    });

    int scheduledMinutes = 0;
    for (final e in taskEvents) {
      scheduledMinutes += e.endTime.difference(e.startTime).inMinutes;
    }
    return scheduledMinutes;
  }

  bool _isTaskScheduled(Task task, List<Event> allEvents) {
    if (task.isCompleted) return true;
    final scheduled = _calculateScheduledTaskMinutes(task, allEvents);
    final target = task.estimatedMinutes ?? 60;
    return scheduled >= target;
  }

  bool _isPrepScheduled(Event event, List<Event> allEvents, DateTime now, SettingsState settings, EventRepository repo) {
    final scheduled = _calculateScheduledPrepMinutes(event, allEvents, now, settings, repo);
    final target = event.prepMinutes ?? 60;
    return scheduled >= target;
  }

  int _calculateScheduledHabitCount(Habit habit, List<Event> allEvents, DateTime weekStart, DateTime weekEnd, SettingsState settings) {
    return allEvents.where((e) {
      if (e.isDeleted) return false;
      final start = TimezoneService.instance.toActiveTime(e.startTime, settings);
      if (start.isBefore(weekStart) || !start.isBefore(weekEnd)) return false;
      final src = e.autoScheduleSource;
      final matchesSource = src != null && (
        src == 'habit:${habit.id}' ||
        src.startsWith('habit:${habit.id};') ||
        src.startsWith('habit:${habit.id}:')
      );
      final matchesTitle = e.title.trim().toLowerCase() == habit.title.trim().toLowerCase();
      return matchesSource || (matchesTitle && (e.isAutoScheduled || e.category == habit.category));
    }).length;
  }

  bool _isHabitScheduled(Habit habit, int completedCount, List<Event> allEvents, DateTime weekStart, DateTime weekEnd, SettingsState settings) {
    final scheduled = _calculateScheduledHabitCount(habit, allEvents, weekStart, weekEnd, settings);
    return (completedCount + scheduled) >= habit.targetFrequencyPerWeek;
  }

  Future<void> _populateWeekHabits(
    BuildContext context,
    WidgetRef ref,
    List<Habit> habits,
    List<Event> allEvents,
    bool isDark,
  ) async {
    final eventDao = ref.read(eventDaoProvider);
    final notificationService = ref.read(notificationServiceProvider);
    final count = await ref.read(habitScheduleProvider.notifier).populateWeek(
      weekSunday: widget.currentWeekStart,
      habits: habits,
      eventDao: eventDao,
      existingEvents: allEvents,
      notificationService: notificationService,
    );
    ref.invalidate(selectedDateEventsProvider);
    ref.invalidate(todayEventsProvider);
    ref.invalidate(allEventsStreamProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: 420,
          backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
          content: Text(
            count > 0
                ? 'Scheduled $count habit sessions from your default template!'
                : 'All habit default slots are already populated for this week.',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildInitWeekCard(
    BuildContext context,
    WidgetRef ref,
    List<Habit> habits,
    List<Event> allEvents,
    bool isDark,
  ) {
    return Container(
      width: 140,
      margin: const EdgeInsets.only(right: 8, bottom: 2),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF231C38) : const Color(0xFFF5EEFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.auto_awesome, color: Colors.purpleAccent, size: 24),
          const SizedBox(height: 6),
          const Text(
            'Init Week',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.purple),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          const Text(
            'Default Habits',
            style: TextStyle(fontSize: 10, color: Colors.purple),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            onPressed: () => _populateWeekHabits(context, ref, habits, allEvents, isDark),
            child: const Text('Populate', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildPrepCard(
    BuildContext context,
    Event event,
    List<Event> allEvents,
    bool isDark, [
    DateTime? nowParam,
    SettingsState? settingsParam,
    EventRepository? eventRepoParam,
  ]) {
    final SettingsState effectiveSettings = settingsParam ?? ref.watch(settingsNotifierProvider);
    final DateTime effectiveNow = nowParam ?? TimezoneService.instance.activeNow(effectiveSettings);
    final EventRepository effectiveRepo = eventRepoParam ?? ref.watch(eventRepositoryProvider);

    final scheduledMinutes = _calculateScheduledPrepMinutes(event, allEvents, effectiveNow, effectiveSettings, effectiveRepo);
    final displayedStart = _getUpcomingPrepStart(event, effectiveNow, effectiveSettings, effectiveRepo);
    final targetPrep = event.prepMinutes ?? 60;
    final progress = targetPrep > 0 ? (scheduledMinutes / targetPrep).clamp(0.0, 1.0) : 0.0;
    final eventStart = TimezoneService.instance.toActiveTime(displayedStart, effectiveSettings);
    final categoryColor = _getCategoryColor(event.category);

    final dragItem = DragScheduleItem(
      type: DragScheduleType.prep,
      title: 'Prep: ${event.title}',
      category: event.category,
      durationMinutes: targetPrep >= 60 ? 60 : targetPrep,
      parentEvent: event,
    );

    return Draggable<DragScheduleItem>(
      data: dragItem,
      feedback: _buildDragFeedback(
        context,
        title: 'Prep: ${event.title}',
        category: event.category,
        durationMinutes: targetPrep >= 60 ? 60 : targetPrep,
        icon: Icons.school,
        badgeText: 'Prep Session • ${_formatMinutes(targetPrep >= 60 ? 60 : targetPrep)}',
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: _buildPrepContainer(event, scheduledMinutes, targetPrep, progress, eventStart, categoryColor, isDark),
      ),
      child: _buildPrepContainer(event, scheduledMinutes, targetPrep, progress, eventStart, categoryColor, isDark),
    );
  }

  Widget _buildPrepContainer(
    Event event,
    int scheduledMinutes,
    int targetPrep,
    double progress,
    DateTime eventStart,
    Color categoryColor,
    bool isDark,
  ) {
    return Container(
      margin: widget.isHorizontal ? const EdgeInsets.only(bottom: 2) : const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.school, size: 14, color: Colors.amber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  event.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'Prep Required',
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Colors.amber),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.drag_indicator, size: 16, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Scheduled: ${_formatMinutes(scheduledMinutes)} / ${_formatMinutes(targetPrep)} target',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: scheduledMinutes >= targetPrep ? Colors.greenAccent : (isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event, size: 11, color: Colors.grey),
                  const SizedBox(width: 3),
                  Text(
                    DateFormat('MMM d • h:mm a').format(eventStart),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(
    BuildContext context,
    Task task,
    List<Event> allEvents,
    bool isDark,
  ) {
    final taskEvents = allEvents.where((e) {
      if (e.isDeleted) return false;
      if (e.autoScheduleSource?.startsWith('task:${task.id}') != true) return false;
      if (task.completedAt != null && e.endTime.isBefore(task.completedAt!)) {
        return false;
      }
      return true;
    }).toList();

    int scheduledMinutes = 0;
    for (final e in taskEvents) {
      scheduledMinutes += e.endTime.difference(e.startTime).inMinutes;
    }

    final duration = task.estimatedMinutes ?? 120; // Default 2 hours session
    final categoryColor = _getCategoryColor(task.category);

    final dragItem = DragScheduleItem(
      type: DragScheduleType.task,
      title: task.title,
      category: task.category,
      durationMinutes: duration,
      task: task,
    );

    return Container(
      margin: widget.isHorizontal ? const EdgeInsets.only(bottom: 2) : const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: categoryColor.withValues(alpha: 0.3),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main task draggable body
          Draggable<DragScheduleItem>(
            data: dragItem,
            feedback: _buildDragFeedback(
              context,
              title: task.title,
              category: task.category,
              durationMinutes: duration,
              icon: Icons.task_alt,
              badgeText: 'Task • ${_formatMinutes(duration)}',
            ),
            childWhenDragging: Opacity(
              opacity: 0.35,
              child: _buildTaskHeader(
                context,
                task,
                scheduledMinutes,
                duration,
                categoryColor,
                isDark,
              ),
            ),
            child: _buildTaskHeader(
              context,
              task,
              scheduledMinutes,
              duration,
              categoryColor,
              isDark,
            ),
          ),

          // Subtasks Stream / List
          Consumer(
            builder: (context, subRef, _) {
              final subtasksAsync = subRef.watch(subtasksForTaskProvider(task.id));
              final subtasks = subtasksAsync.value ?? [];
              if (subtasks.isEmpty) return const SizedBox.shrink();

              final incompleteSubtasks = subtasks.where((s) => !s.isCompleted).toList();
              if (incompleteSubtasks.isEmpty) return const SizedBox.shrink();

              return Container(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF161F2E).withValues(alpha: 0.5)
                      : const Color(0xFFF1F5F9).withValues(alpha: 0.6),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(
                        'Subtasks (${incompleteSubtasks.length} remaining • Drag onto calendar):',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ),
                    ...incompleteSubtasks.map((subtask) => _buildSubtaskDraggablePill(
                          context,
                          task,
                          subtask,
                          categoryColor,
                          isDark,
                        )),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTaskHeader(
    BuildContext context,
    Task task,
    int scheduledMinutes,
    int duration,
    Color categoryColor,
    bool isDark,
  ) {
    final progress = duration > 0 ? (scheduledMinutes / duration).clamp(0.0, 1.0) : 0.0;
    final settings = ref.watch(settingsNotifierProvider);
    final dueDate = TimezoneService.instance.toActiveTime(task.dueDate, settings);
    final now = TimezoneService.instance.activeNow(settings);
    final isDueSoon = dueDate.difference(now).inDays <= 1;

    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: categoryColor,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  task.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _formatMinutes(duration),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: categoryColor,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.drag_indicator, size: 16, color: Colors.grey),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Scheduled: ${_formatMinutes(scheduledMinutes)}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: scheduledMinutes > 0 ? categoryColor : (isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.event,
                    size: 11,
                    color: isDueSoon ? Colors.redAccent : Colors.grey,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    DateFormat('MMM d').format(dueDate),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: isDueSoon ? FontWeight.bold : FontWeight.normal,
                      color: isDueSoon ? Colors.redAccent : Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(categoryColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtaskDraggablePill(
    BuildContext context,
    Task task,
    Subtask subtask,
    Color categoryColor,
    bool isDark,
  ) {
    final subtaskDuration = (task.estimatedMinutes ?? 120) >= 60 ? 60 : (task.estimatedMinutes ?? 120);

    final dragItem = DragScheduleItem(
      type: DragScheduleType.subtask,
      title: '${task.title}: ${subtask.title}',
      category: task.category,
      durationMinutes: subtaskDuration,
      task: task,
      subtask: subtask,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Draggable<DragScheduleItem>(
        data: dragItem,
        feedback: _buildDragFeedback(
          context,
          title: '${task.title}: ${subtask.title}',
          category: task.category,
          durationMinutes: subtaskDuration,
          icon: Icons.subdirectory_arrow_right,
          badgeText: 'Subtask • ${_formatMinutes(subtaskDuration)}',
        ),
        childWhenDragging: Opacity(
          opacity: 0.35,
          child: _buildSubtaskRow(task, subtask, categoryColor, isDark),
        ),
        child: _buildSubtaskRow(task, subtask, categoryColor, isDark),
      ),
    );
  }

  Widget _buildSubtaskRow(
    Task task,
    Subtask subtask,
    Color categoryColor,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: categoryColor.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () async {
              await ref.read(taskDaoProvider).toggleSubtask(subtask.id, true);
              ref.invalidate(subtasksForTaskProvider(task.id));
            },
            child: const Icon(Icons.circle_outlined, size: 14, color: Colors.grey),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              subtask.title,
              style: const TextStyle(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.drag_indicator, size: 14, color: Colors.grey),
        ],
      ),
    );
  }

  Widget _buildDragFeedback(
    BuildContext context, {
    required String title,
    required String category,
    required int durationMinutes,
    required IconData icon,
    required String badgeText,
  }) {
    final catColor = _getCategoryColor(category);

    return Material(
      color: Colors.transparent,
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 170,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: catColor,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: Colors.white),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  String _formatMinutes(int minutes) {
    if (minutes == 0) return '0h';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
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
