// lib/data/database/daos/task_dao.dart
//
// Data-access object for Tasks and hierarchical Subtasks.

import 'package:drift/drift.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/database/tables/tasks_table.dart';
import 'package:kairos/data/database/tables/subtasks_table.dart';
import 'package:kairos/data/database/daos/restore_timestamp.dart';

part 'task_dao.g.dart';

@DriftAccessor(tables: [Tasks, Subtasks])
class TaskDao extends DatabaseAccessor<AppDatabase> with _$TaskDaoMixin {
  TaskDao(super.db);

  // ── Task Queries ──────────────────────────────────────────────────────────

  Future<List<Task>> getAllTasks() =>
      (select(tasks)..where((t) => t.isDeleted.equals(false))
        ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
          .get();

  /// All non-deleted incomplete tasks.
  Future<List<Task>> getIncompleteTasks() =>
      (select(tasks)
            ..where((t) => t.isDeleted.equals(false) & t.isCompleted.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
          .get();

  /// Incomplete tasks whose deadline falls within or before [end].
  Future<List<Task>> getIncompleteTasksDueBefore(DateTime end) =>
      (select(tasks)
            ..where(
              (t) =>
                  t.isDeleted.equals(false) &
                  t.isCompleted.equals(false) &
                  t.dueDate.isSmallerOrEqualValue(end),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
          .get();

  Future<Task?> getTaskById(int id) =>
      (select(tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<List<Task>> watchIncompleteTasks() =>
      (select(tasks)
            ..where(
                (t) => t.isDeleted.equals(false) & t.isCompleted.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
          .watch();

  Stream<List<Task>> watchTasksDueSoon(DateTime threshold) =>
      (select(tasks)
            ..where(
              (t) =>
                  t.isDeleted.equals(false) &
                  t.isCompleted.equals(false) &
                  t.dueDate.isSmallerOrEqualValue(threshold),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
          .watch();

  Stream<List<Task>> watchTasksForCategory(String category) =>
      (select(tasks)
            ..where((t) => t.isDeleted.equals(false) & t.category.equals(category))
            ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
          .watch();

  // ── Task Mutations ────────────────────────────────────────────────────────

  Future<int> insertTask(TasksCompanion companion) =>
      into(tasks).insert(companion);

  Future<bool> updateTask(TasksCompanion companion) =>
      update(tasks).replace(companion);

  Future<int> markCompleted(int id) => (update(tasks)
        ..where((t) => t.id.equals(id)))
      .write(TasksCompanion(
        isCompleted: const Value(true),
        completedAt: Value(DateTime.now().toUtc()),
        updatedAt: Value(DateTime.now().toUtc()),
      ));

  Future<bool> completeTask(int id) async {
    final rows = await markCompleted(id);
    return rows > 0;
  }

  Future<int> deleteTask(int id) => (update(tasks)
        ..where((t) => t.id.equals(id)))
      .write(TasksCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now().toUtc()),
      ));

  /// Reverses [deleteTask] (undo). See [restoreTimestamp] for why the timestamp is bumped.
  Future<int> restoreTask(int id) => transaction(() async {
        final row = await (select(tasks)..where((t) => t.id.equals(id))).getSingle();
        return (update(tasks)..where((t) => t.id.equals(id))).write(TasksCompanion(
          isDeleted: const Value(false),
          updatedAt: Value(restoreTimestamp(row.updatedAt)),
        ));
      });

  // ── Subtask Queries & Mutations ───────────────────────────────────────────

  Future<List<Subtask>> getSubtasksForTask(int taskId) =>
      (select(subtasks)
            ..where((s) => s.taskId.equals(taskId))
            ..orderBy([(s) => OrderingTerm.asc(s.id)]))
          .get();

  Stream<List<Subtask>> watchSubtasksForTask(int taskId) =>
      (select(subtasks)
            ..where((s) => s.taskId.equals(taskId))
            ..orderBy([(s) => OrderingTerm.asc(s.id)]))
          .watch();

  Future<int> insertSubtask(SubtasksCompanion subtask) =>
      into(subtasks).insert(subtask);

  Future<int> toggleSubtask(int subtaskId, bool isCompleted) =>
      (update(subtasks)..where((s) => s.id.equals(subtaskId))).write(
        SubtasksCompanion(isCompleted: Value(isCompleted)),
      );

  Future<int> deleteSubtask(int subtaskId) =>
      (delete(subtasks)..where((s) => s.id.equals(subtaskId))).go();

  Future<int> resetSubtasksForTask(int taskId) =>
      (update(subtasks)..where((s) => s.taskId.equals(taskId))).write(
        const SubtasksCompanion(isCompleted: Value(false)),
      );
}
