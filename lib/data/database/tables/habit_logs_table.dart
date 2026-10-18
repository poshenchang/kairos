// lib/data/database/tables/habit_logs_table.dart
//
// Drift table definition for individual habit completion records.

import 'package:drift/drift.dart';
import 'habits_table.dart';

/// Each row represents one completed session of a habit.
/// The auto-scheduler reads this table to determine how many sessions
/// have already been completed in the current week.
class HabitLogs extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// The habit this log entry belongs to.
  IntColumn get habitId =>
      integer().references(Habits, #id, onDelete: KeyAction.cascade)();

  /// UTC timestamp of when the session was completed (or started).
  DateTimeColumn get completedAt => dateTime()();

  /// Duration of the completed session in minutes.
  IntColumn get durationMinutes => integer().nullable()();

  /// Optional notes about the session.
  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
