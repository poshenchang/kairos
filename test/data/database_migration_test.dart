// test/data/database_migration_test.dart

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('migration from v3 without updated_at columns succeeds and sets values', () async {
    final rawSqlite = sqlite3.openInMemory();
    rawSqlite.execute('''
      PRAGMA user_version = 3;
      CREATE TABLE IF NOT EXISTS "categories" (
        "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        "name" TEXT NOT NULL,
        "slug" TEXT NOT NULL UNIQUE,
        "emoji" TEXT NOT NULL DEFAULT '📌',
        "color_hex" TEXT NOT NULL DEFAULT '#4A90D9',
        "is_system" INTEGER NOT NULL DEFAULT 0,
        "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
      );
      CREATE TABLE IF NOT EXISTS "events" (
        "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        "title" TEXT NOT NULL,
        "category" TEXT NOT NULL DEFAULT 'other',
        "event_type" TEXT NULL,
        "start_time" INTEGER NOT NULL,
        "end_time" INTEGER NOT NULL,
        "is_recurring" INTEGER NOT NULL DEFAULT 0,
        "rrule" TEXT NULL,
        "requires_prep" INTEGER NOT NULL DEFAULT 0,
        "prep_minutes" INTEGER NULL,
        "is_auto_scheduled" INTEGER NOT NULL DEFAULT 0,
        "auto_schedule_source" TEXT NULL,
        "notes" TEXT NULL,
        "is_deleted" INTEGER NOT NULL DEFAULT 0,
        "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
        "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
      );
      CREATE TABLE IF NOT EXISTS "tasks" (
        "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        "title" TEXT NOT NULL,
        "category" TEXT NOT NULL DEFAULT 'other',
        "description" TEXT NULL,
        "due_date" INTEGER NOT NULL,
        "estimated_minutes" INTEGER NULL,
        "priority" INTEGER NOT NULL DEFAULT 3,
        "is_recurring" INTEGER NOT NULL DEFAULT 0,
        "rrule" TEXT NULL,
        "is_completed" INTEGER NOT NULL DEFAULT 0,
        "completed_at" INTEGER NULL,
        "is_deleted" INTEGER NOT NULL DEFAULT 0,
        "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
        "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
      );
      CREATE TABLE IF NOT EXISTS "habits" (
        "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        "title" TEXT NOT NULL,
        "category" TEXT NOT NULL DEFAULT 'personal',
        "description" TEXT NULL,
        "target_frequency_per_week" INTEGER NOT NULL DEFAULT 1,
        "min_session_minutes" INTEGER NOT NULL DEFAULT 30,
        "max_session_minutes" INTEGER NOT NULL DEFAULT 60,
        "preferred_window" TEXT NOT NULL DEFAULT 'any',
        "days_filter" TEXT NOT NULL DEFAULT 'all',
        "is_active" INTEGER NOT NULL DEFAULT 1,
        "is_deleted" INTEGER NOT NULL DEFAULT 0,
        "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER)),
        "updated_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
      );
      CREATE TABLE IF NOT EXISTS "habit_logs" (
        "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        "habit_id" INTEGER NOT NULL,
        "completed_at" INTEGER NOT NULL,
        "duration_minutes" INTEGER NULL,
        "notes" TEXT NULL,
        "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
      );
      CREATE TABLE IF NOT EXISTS "holidays" (
        "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        "name" TEXT NOT NULL,
        "group_name" TEXT NOT NULL DEFAULT 'US Holidays',
        "date" INTEGER NOT NULL,
        "end_date" INTEGER NULL,
        "is_enabled" INTEGER NOT NULL DEFAULT 1
      );
      CREATE TABLE IF NOT EXISTS "subtasks" (
        "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        "task_id" INTEGER NOT NULL,
        "title" TEXT NOT NULL,
        "is_completed" INTEGER NOT NULL DEFAULT 0,
        "created_at" INTEGER NOT NULL DEFAULT (CAST(strftime('%s', CURRENT_TIMESTAMP) AS INTEGER))
      );

      -- Insert sample data in v3 schema
      INSERT INTO "categories" ("name", "slug") VALUES ('School', 'school');
      INSERT INTO "habits" ("title") VALUES ('Exercise');
      INSERT INTO "habit_logs" ("habit_id", "completed_at") VALUES (1, 1000000);
    ''');

    final executor = NativeDatabase.opened(rawSqlite);
    final db = AppDatabase.forTesting(executor);

    // Opening database triggers onUpgrade(m, 3, 4)
    final categories = await db.select(db.categories).get();
    expect(categories.length, 1);
    expect(categories.first.name, 'School');
    expect(categories.first.updatedAt != null, isTrue);

    final habitLogs = await db.select(db.habitLogs).get();
    expect(habitLogs.length, 1);
    expect(habitLogs.first.updatedAt != null, isTrue);

    await db.close();
  });
}
