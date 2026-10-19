// lib/data/database/tables/categories_table.dart
//
// Drift table definition for event/task/habit categories.

import 'package:drift/drift.dart';

/// Categories allow users to organize events, tasks, and habits
/// (e.g. Schoolwork, Work, Research, Personal, Transportation, or custom).
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get syncId => text().nullable()();

  /// Display name (e.g. "Schoolwork", "Research", "Piano")
  TextColumn get name => text().withLength(min: 1, max: 100)();

  /// Slug identifier (e.g. "schoolwork", "work", "research", "personal", "transportation")
  TextColumn get slug => text().unique()();

  /// Display emoji icon (e.g. "🎓", "💼", "🔬", "🧘", "🚆")
  TextColumn get emoji => text().withDefault(const Constant('📌'))();

  /// Hex color code (e.g. "#4A90D9")
  TextColumn get colorHex => text().withDefault(const Constant('#4A90D9'))();

  /// True for built-in default categories that cannot be deleted
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();

  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

