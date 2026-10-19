// lib/ui/screens/tasks/tasks_screen.dart
//
// Tasks & Deadlines screen:
// - Hierarchical subtasks under tasks (with checkboxes, progress bar, inline adder)
// - Category filters, overdue alerts, completion toggle, focus timer
// - Consistent top-right AppGlobalActions

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/widgets/add_task_dialog.dart';
import 'package:kairos/ui/widgets/edit_task_dialog.dart';
import 'package:kairos/ui/widgets/app_global_actions.dart';
import 'package:kairos/ui/widgets/category_badge.dart';
import 'package:kairos/ui/widgets/focus_timer_dialog.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  String? _selectedCategory;
  bool _showCompleted = false;

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(allCategoriesProvider);
    final categories = categoriesAsync.value ?? [];
    final tasksDao = ref.watch(taskDaoProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks & Deadlines', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: const [
          AppGlobalActions(showAddButtons: false),
        ],
      ),
      body: Column(
        children: [
          // Filter Row: Completed Toggle & Category Chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                FilterChip(
                  label: Text(_showCompleted ? 'Showing Completed' : 'Active Only'),
                  selected: _showCompleted,
                  onSelected: (val) => setState(() => _showCompleted = val),
                  avatar: Icon(_showCompleted ? Icons.check_circle : Icons.circle_outlined, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ChoiceChip(
                          label: const Text('All'),
                          selected: _selectedCategory == null,
                          onSelected: (_) => setState(() => _selectedCategory = null),
                        ),
                        const SizedBox(width: 6),
                        ...categories.map((cat) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 6.0),
                            child: ChoiceChip(
                              label: Text('${cat.emoji} ${cat.name}'),
                              selected: _selectedCategory == cat.slug,
                              onSelected: (val) {
                                setState(() => _selectedCategory = val ? cat.slug : null);
                              },
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Task List Stream
          Expanded(
            child: StreamBuilder<List<Task>>(
              stream: _showCompleted
                  ? tasksDao.watchTasksDueSoon(DateTime.now().add(const Duration(days: 365)))
                  : tasksDao.watchIncompleteTasks(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var tasks = snapshot.data ?? [];

                // Filter by category
                if (_selectedCategory != null) {
                  tasks = tasks.where((t) => t.category == _selectedCategory).toList();
                }

                if (tasks.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
                        const SizedBox(height: 12),
                        Text(
                          _showCompleted ? 'No completed tasks found.' : 'All caught up! No active tasks.',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Add a problem set, project deadline, or reading assignment below.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }

                final now = DateTime.now();

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return _TaskCardWithSubtasks(
                      task: task,
                      now: now,
                      tasksDao: tasksDao,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AddTaskDialog.show(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Task'),
      ),
    );
  }
}

class _TaskCardWithSubtasks extends ConsumerStatefulWidget {
  final Task task;
  final DateTime now;
  final TaskDao tasksDao;

  const _TaskCardWithSubtasks({
    required this.task,
    required this.now,
    required this.tasksDao,
  });

  @override
  ConsumerState<_TaskCardWithSubtasks> createState() => _TaskCardWithSubtasksState();
}

class _TaskCardWithSubtasksState extends ConsumerState<_TaskCardWithSubtasks> {
  final TextEditingController _subtaskCtrl = TextEditingController();
  bool _isExpanded = true;
  bool _showAddSubtask = false;

  @override
  void dispose() {
    _subtaskCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final isOverdue = task.dueDate.isBefore(widget.now) && !task.isCompleted;
    final hoursUntil = task.dueDate.difference(widget.now).inHours;
    final isUrgent = hoursUntil <= 24 && !task.isCompleted;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isOverdue
              ? Colors.red.shade400
              : (isUrgent ? Colors.orange.shade400 : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
          width: (isOverdue || isUrgent) ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Task Main Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: task.isCompleted,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  onChanged: (val) async {
                    if (val == true) {
                      await ref.read(taskRepositoryProvider).completeTask(task.id);
                    } else {
                      await widget.tasksDao.updateTask(task.toCompanion(true).copyWith(isCompleted: const Value(false)));
                    }
                    ref.invalidate(dashboardTasksProvider);
                    ref.invalidate(incompleteTasksStreamProvider);
                  },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                          color: task.isCompleted ? Colors.grey : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          CategoryBadge(categorySlugOrName: task.category, compact: true),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.alarm,
                            size: 13,
                            color: isOverdue ? Colors.red : Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('MMM d, HH:mm').format(task.dueDate),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: (isOverdue || isUrgent) ? FontWeight.bold : FontWeight.normal,
                              color: isOverdue
                                  ? Colors.red
                                  : (isUrgent ? Colors.orange.shade800 : Colors.grey),
                            ),
                          ),
                          if (task.isRecurring) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.repeat, size: 12, color: Colors.grey),
                            const SizedBox(width: 2),
                            const Text('Weekly', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ],
                      ),
                      if (task.description != null && task.description!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                            task.description!,
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.timer_outlined, color: Colors.blueAccent),
                  tooltip: 'Start Focus Timer (25m)',
                  onPressed: () {
                    FocusTimerDialog.show(
                      context,
                      title: task.title,
                      category: task.category,
                      defaultMinutes: 25,
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.blueGrey),
                  tooltip: 'Edit Task',
                  onPressed: () => EditTaskDialog.show(context, task),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                  tooltip: 'Delete Task',
                  onPressed: () async {
                    await widget.tasksDao.deleteTask(task.id);
                    ref.invalidate(dashboardTasksProvider);
                    ref.invalidate(incompleteTasksStreamProvider);
                  },
                ),
              ],
            ),

            // ── SUBTASKS SECTION ───────────────────────────────────────────
            StreamBuilder<List<Subtask>>(
              stream: widget.tasksDao.watchSubtasksForTask(task.id),
              builder: (context, subSnapshot) {
                final subtasks = subSnapshot.data ?? [];
                final completedCount = subtasks.where((s) => s.isCompleted).length;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subtasks.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      // Progress Bar & Count
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: subtasks.isEmpty ? 0 : (completedCount / subtasks.length),
                                minHeight: 6,
                                backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  completedCount == subtasks.length ? Colors.green : Colors.blueAccent,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '$completedCount/${subtasks.length} subtasks',
                            style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more, size: 18),
                            onPressed: () => setState(() => _isExpanded = !_isExpanded),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      if (_isExpanded) ...[
                        const SizedBox(height: 4),
                        ...subtasks.map((st) {
                          return Padding(
                            padding: const EdgeInsets.only(left: 20.0, top: 2.0),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: Checkbox(
                                    value: st.isCompleted,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                                    onChanged: (val) async {
                                      await widget.tasksDao.toggleSubtask(st.id, val ?? false);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    st.title,
                                    style: TextStyle(
                                      fontSize: 13,
                                      decoration: st.isCompleted ? TextDecoration.lineThrough : null,
                                      color: st.isCompleted ? Colors.grey : null,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 14, color: Colors.grey),
                                  onPressed: () async {
                                    await widget.tasksDao.deleteSubtask(st.id);
                                  },
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],

                    // Inline "+ Add Subtask"
                    if (_showAddSubtask) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 20.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _subtaskCtrl,
                                autofocus: true,
                                style: const TextStyle(fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: 'Subtask title (e.g. Read chapter 2, solve #3)...',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: (_) => _addSubtask(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _addSubtask,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              child: const Text('Add'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() => _showAddSubtask = false),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.only(left: 20.0, top: 4.0),
                        child: TextButton.icon(
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Add subtask', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => setState(() => _showAddSubtask = true),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addSubtask() async {
    final title = _subtaskCtrl.text.trim();
    if (title.isEmpty) return;

    await widget.tasksDao.insertSubtask(
      SubtasksCompanion.insert(
        taskId: widget.task.id,
        title: title,
      ),
    );

    _subtaskCtrl.clear();
    setState(() => _showAddSubtask = false);
  }
}
