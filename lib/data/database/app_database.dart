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
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(holidays);
            await m.createTable(subtasks);
          }
          if (from < 3) {
            await m.addColumn(holidays, holidays.groupName);
            await m.addColumn(habits, habits.daysFilter);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
