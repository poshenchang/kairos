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
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/habit_schedule_service.dart';
import 'package:kairos/services/notification_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/screens/calendar/widgets/drag_schedule_item.dart';
import 'package:kairos/ui/widgets/add_event_dialog.dart';
import 'package:kairos/ui/widgets/add_habit_dialog.dart';
import 'package:kairos/ui/widgets/add_task_dialog.dart';
import 'package:kairos/ui/widgets/habit_schedule_dialog.dart';

class ScheduleSidebar extends ConsumerStatefulWidget {
  final DateTime currentWeekStart;
  final VoidCallback? onClose;

  const ScheduleSidebar({
    super.key,
    required this.currentWeekStart,
    this.onClose,
  });

  @override
  ConsumerState<ScheduleSidebar> createState() => _ScheduleSidebarState();
}

class _ScheduleSidebarState extends ConsumerState<ScheduleSidebar> {
  String _selectedTab = 'all'; // 'all', 'tasks', 'habits', 'preps'

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final tasksAsync = ref.watch(incompleteTasksStreamProvider);
    final habitsAsync = ref.watch(activeHabitsProvider);
    final completionsAsync = ref.watch(habitCompletionsForWeekProvider(widget.currentWeekStart));
    final allEventsAsync = ref.watch(allEventsStreamProvider);
    final habitSchedules = ref.watch(habitScheduleProvider);

    final tasks = tasksAsync.value ?? [];
    final habits = habitsAsync.value ?? [];
    final completions = completionsAsync.value ?? {};
    final allEvents = allEventsAsync.value ?? [];

    // Filter upcoming events that require preparation (Exams, Interviews, Presentations)
    final prepEvents = allEvents.where((e) {
      return e.requiresPrep &&
          !e.isAutoScheduled &&
          e.startTime.isAfter(DateTime.now().subtract(const Duration(hours: 2)));
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final totalCount = tasks.length + habits.length + prepEvents.length;

    return Container(
      color: isDark ? const Color(0xFF131A2A) : const Color(0xFFF8FAFC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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

          // Filter Segmented Control
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
                    value: 'habits',
                    label: Text('Habits (${habits.length})', style: const TextStyle(fontSize: 10.5)),
                  ),
                  ButtonSegment(
                    value: 'preps',
                    label: Text('Preps (${prepEvents.length})', style: const TextStyle(fontSize: 10.5)),
                  ),
                  ButtonSegment(
                    value: 'tasks',
                    label: Text('Tasks (${tasks.length})', style: const TextStyle(fontSize: 10.5)),
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
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              children: [
                // ── Habits Section ──
                if (_selectedTab == 'all' || _selectedTab == 'habits') ...[
                  _buildSectionHeader(
                    context,
                    title: 'Active Habits',
                    icon: Icons.repeat,
                    count: habits.length,
                    onAdd: () => AddHabitDialog.show(context),
                  ),

                  // Initialize Week with Default Schedule Button
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
                        onPressed: () async {
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
                        },
                      ),
                    ),

                  if (habits.isEmpty)
                    _buildEmptyState('No active habits', 'Create one to schedule regular practice')
                  else
                    ...habits.map((habit) => _buildHabitCard(
                          context,
                          habit,
                          completions,
                          allEvents,
                          habitSchedules[habit.id] ?? [],
                          isDark,
                        )),
                  const SizedBox(height: 14),
                ],

                // ── Exam & Interview Preps Section ──
                if (_selectedTab == 'all' || _selectedTab == 'preps') ...[
                  _buildSectionHeader(
                    context,
                    title: 'Exam & Interview Preps',
                    icon: Icons.school_outlined,
                    count: prepEvents.length,
                    onAdd: () => AddEventDialog.show(context),
                  ),
                  if (prepEvents.isEmpty)
                    _buildEmptyState('No exam/interview preps needed', 'Create an event with "Requires Prep" enabled')
                  else
                    ...prepEvents.map((event) => _buildPrepCard(context, event, allEvents, isDark)),
                  const SizedBox(height: 14),
                ],

                // ── Tasks Section ──
                if (_selectedTab == 'all' || _selectedTab == 'tasks') ...[
                  _buildSectionHeader(
                    context,
                    title: 'Tasks & Deadlines',
                    icon: Icons.check_circle_outline,
                    count: tasks.length,
                    onAdd: () => AddTaskDialog.show(context),
                  ),
                  if (tasks.isEmpty)
                    _buildEmptyState('All tasks caught up!', 'Add a new deadline to get started')
                  else
                    ...tasks.map((task) => _buildTaskCard(context, task, allEvents, isDark)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required IconData icon,
    required int count,
    required VoidCallback onAdd,
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

    // Scheduled events for this habit this week
    final habitWeekEvents = allEvents.where((e) {
      if (e.isDeleted) return false;
      final start = e.startTime.toLocal();
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
      margin: const EdgeInsets.only(bottom: 8),
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

  Widget _buildPrepCard(
    BuildContext context,
    Event event,
    List<Event> allEvents,
    bool isDark,
  ) {
    // Total scheduled prep minutes for this event
    final prepEvents = allEvents.where((e) {
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
    }).toList();

    int scheduledMinutes = 0;
    for (final e in prepEvents) {
      scheduledMinutes += e.endTime.difference(e.startTime).inMinutes;
    }

    final targetPrep = event.prepMinutes ?? 60;
    final progress = targetPrep > 0 ? (scheduledMinutes / targetPrep).clamp(0.0, 1.0) : 0.0;
    final eventStart = event.startTime.toLocal();
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
      margin: const EdgeInsets.only(bottom: 8),
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
      return e.autoScheduleSource?.startsWith('task:${task.id}') == true;
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
      margin: const EdgeInsets.only(bottom: 8),
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
    final dueDate = task.dueDate.toLocal();
    final now = DateTime.now();
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
