// lib/data/database/tables/tasks_table.dart
//
// Drift table definition for tasks (one-off or recurring deadlines).

import 'package:drift/drift.dart';

/// A task is a deadline-bound piece of work that the user needs to complete.
/// Unlike events, tasks do not have a fixed start time — they have a due date.
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get title => text().withLength(min: 1, max: 200)();

  TextColumn get category => text().withDefault(const Constant('other'))();

  /// Optional detailed description.
  TextColumn get description => text().nullable()();

  /// UTC deadline for the task.
  DateTimeColumn get dueDate => dateTime()();

  /// Estimated effort in minutes (used by scheduler for prep blocks).
  IntColumn get estimatedMinutes => integer().nullable()();

  /// Priority: 1 (low) – 5 (critical).
  IntColumn get priority => integer().withDefault(const Constant(3))();

  /// Whether this task recurs.
  BoolColumn get isRecurring => boolean().withDefault(const Constant(false))();

  /// RFC 5545 RRULE for recurring tasks.
  TextColumn get rrule => text().nullable()();

  /// Whether the task has been completed.
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();

  /// When the task was completed.
  DateTimeColumn get completedAt => dateTime().nullable()();

  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
