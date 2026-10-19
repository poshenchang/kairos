// lib/data/database/app_database.dart
//
// Drift database definition for Kairos.
// Run `dart run build_runner build` to generate app_database.g.dart.

import 'package:drift/drift.dart';
import 'connection/connection.dart' as conn;

import 'tables/categories_table.dart';
import 'tables/events_table.dart';
import 'tables/tasks_table.dart';
import 'tables/habits_table.dart';
import 'tables/habit_logs_table.dart';
import 'tables/holidays_table.dart';
import 'tables/subtasks_table.dart';
import 'daos/category_dao.dart';
import 'daos/event_dao.dart';
import 'daos/task_dao.dart';
import 'daos/habit_dao.dart';
import 'daos/holiday_dao.dart';

export 'tables/categories_table.dart';
export 'tables/events_table.dart';
export 'tables/tasks_table.dart';
export 'tables/habits_table.dart';
export 'tables/habit_logs_table.dart';
export 'tables/holidays_table.dart';
export 'tables/subtasks_table.dart';
export 'daos/category_dao.dart';
export 'daos/event_dao.dart';
export 'daos/task_dao.dart';
export 'daos/habit_dao.dart';
export 'daos/holiday_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Categories, Events, Tasks, Habits, HabitLogs, Holidays, Subtasks],
  daos: [CategoryDao, EventDao, TaskDao, HabitDao, HolidayDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(conn.openConnection());

  AppDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await _safeCreateTable(m, holidays);
            await _safeCreateTable(m, subtasks);
          }
          if (from < 3) {
            await _safeAddColumn(m, holidays, holidays.groupName);
            await _safeAddColumn(m, habits, habits.daysFilter);
          }
          if (from < 4) {
            await _safeAddColumn(m, events, events.syncId);
            await _safeAddColumn(m, tasks, tasks.syncId);
            await _safeAddColumn(m, habits, habits.syncId);
            await _safeAddColumn(m, habitLogs, habitLogs.syncId);
            await _safeAddTimestampColumn('habit_logs', 'updated_at');
            await _safeAddColumn(m, holidays, holidays.syncId);
            await _safeAddColumn(m, holidays, holidays.isDeleted);
            await _safeAddTimestampColumn('holidays', 'updated_at');
            await _safeAddColumn(m, categories, categories.syncId);
            await _safeAddColumn(m, categories, categories.isDeleted);
            await _safeAddTimestampColumn('categories', 'updated_at');
            await _safeAddColumn(m, subtasks, subtasks.syncId);
            await _safeAddColumn(m, subtasks, subtasks.isDeleted);
            await _safeAddTimestampColumn('subtasks', 'updated_at');
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _safeCreateTable(Migrator m, TableInfo table) async {
    try {
      await m.createTable(table);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (!msg.contains('already exists')) {
        rethrow;
      }
    }
  }

  Future<void> _safeAddTimestampColumn(
    String tableName,
    String columnName,
  ) async {
    try {
      final rows = await customSelect('PRAGMA table_info("$tableName")').get();
      final columnNames = rows.map((r) => r.read<String>('name')).toSet();
      if (columnNames.contains(columnName)) {
        return;
      }
    } catch (_) {}

    try {
      // SQLite ALTER TABLE requires a constant literal default (expressions like
      // CURRENT_TIMESTAMP are rejected). We use DEFAULT 0 and then backfill.
      await customStatement('ALTER TABLE "$tableName" ADD COLUMN "$columnName" INTEGER NOT NULL DEFAULT 0;');
      await customStatement(
        'UPDATE "$tableName" SET "$columnName" = CAST(strftime(\'%s\', CURRENT_TIMESTAMP) AS INTEGER) WHERE "$columnName" = 0;',
      );
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (!msg.contains('duplicate column') && !msg.contains('already exists')) {
        rethrow;
      }
    }
  }

  Future<void> _safeAddColumn(
    Migrator m,
    TableInfo table,
    GeneratedColumn column,
  ) async {
    try {
      final rows = await customSelect('PRAGMA table_info("${table.actualTableName}")').get();
      final columnNames = rows.map((r) => r.read<String>('name')).toSet();
      if (columnNames.contains(column.name)) {
        return;
      }
    } catch (_) {
      // If PRAGMA check fails for any reason, proceed to attempt addColumn
    }

    try {
      await m.addColumn(table, column);
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('non-constant default')) {
        // Fallback for SQLite when an expression default was attempted
        final isText = column.type == DriftSqlType.string;
        final sqlDefault = isText ? "DEFAULT ''" : "DEFAULT 0";
        final sqlType = isText ? 'TEXT' : 'INTEGER';
        await customStatement('ALTER TABLE "${table.actualTableName}" ADD COLUMN "${column.name}" $sqlType NOT NULL $sqlDefault;');
        return;
      }
      if (!msg.contains('duplicate column') && !msg.contains('already exists')) {
        rethrow;
      }
    }
  }
}
