// lib/data/database/tables/habits_table.dart
//
// Drift table definition for habits (frequency-based activities).

import 'package:drift/drift.dart';

/// A habit is a recurring activity tracked by frequency (e.g. "run 3×/week")
/// rather than by a fixed schedule. The auto-scheduler inserts habit sessions
/// into free slots to meet the weekly target.
class Habits extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get title => text().withLength(min: 1, max: 200)();

  TextColumn get category => text().withDefault(const Constant('personal'))();

  TextColumn get description => text().nullable()();

  /// Target sessions per week (e.g. 3 for "3×/week").
  IntColumn get targetFrequencyPerWeek =>
      integer().withDefault(const Constant(1))();

  /// Minimum duration of a single session in minutes.
  IntColumn get minSessionMinutes =>
      integer().withDefault(const Constant(30))();

  /// Maximum duration of a single session in minutes.
  IntColumn get maxSessionMinutes =>
      integer().withDefault(const Constant(60))();

  /// Preferred time-of-day: "morning" | "afternoon" | "evening" | "any".
  TextColumn get preferredWindow =>
      text().withDefault(const Constant('any'))();

  /// Whether the habit is currently active (visible to scheduler).
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
