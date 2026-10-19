// test/services/timezone_service_test.dart
//
// Tests for TimezoneService: wall-clock parsing/serialization, offset calculation,
// and database schedule shift alignment.

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/timezone_service.dart';

void main() {
  group('TimezoneService - Parsing & Formatting', () {
    final tz = TimezoneService.instance;

    test('parseRemoteTimestamp correctly extracts wall-clock time from UTC string', () {
      // Supabase TIMESTAMPTZ returns with +00:00 suffix
      final dt1 = tz.parseRemoteTimestamp('2026-10-19T09:00:00+00:00');
      expect(dt1.year, 2026);
      expect(dt1.month, 10);
      expect(dt1.day, 19);
      expect(dt1.hour, 9);
      expect(dt1.minute, 0);
      expect(dt1.second, 0);
      expect(dt1.isUtc, false);

      // Trailing 'Z'
      final dt2 = tz.parseRemoteTimestamp('2026-10-19T15:30:45Z');
      expect(dt2.hour, 15);
      expect(dt2.minute, 30);
      expect(dt2.second, 45);

      // Milliseconds preserved
      final dt3 = tz.parseRemoteTimestamp('2026-10-19T11:20:30.123+00:00');
      expect(dt3.hour, 11);
      expect(dt3.minute, 20);
      expect(dt3.second, 30);
      expect(dt3.millisecond, 123);

      // Date only
      final dtDate = tz.parseRemoteTimestamp('2026-12-25');
      expect(dtDate.year, 2026);
      expect(dtDate.month, 12);
      expect(dtDate.day, 25);
    });

    test('formatForRemoteSync creates ISO wall-clock string without offset distortion', () {
      final dt = DateTime(2026, 10, 19, 9, 5, 0);
      final formatted = tz.formatForRemoteSync(dt);
      expect(formatted, '2026-10-19T09:05:00.000');
    });

    test('getActiveOffset respects manual vs auto settings', () {
      const autoSettings = SettingsState(timezoneMode: 'auto');
      expect(tz.getActiveOffset(autoSettings), DateTime.now().timeZoneOffset);

      const manualSettings = SettingsState(
        timezoneMode: 'manual',
        manualTimezoneOffsetMinutes: 480, // UTC+8
      );
      expect(tz.getActiveOffset(manualSettings), const Duration(hours: 8));

      const manualNySettings = SettingsState(
        timezoneMode: 'manual',
        manualTimezoneOffsetMinutes: -300, // UTC-5
      );
      expect(tz.getActiveOffset(manualNySettings), const Duration(hours: -5));
    });
  });

  group('TimezoneService - Schedule Shift Repair Tool', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('shiftAllEventsAndTasks shifts events and tasks back by 8 hours', () async {
      final tz = TimezoneService.instance;

      // Create an event at 17:00 (shifted by bug)
      final eventId = await db.eventDao.insertEvent(
        EventsCompanion.insert(
          title: 'Shifted Class',
          startTime: DateTime(2026, 10, 19, 17, 0),
          endTime: DateTime(2026, 10, 19, 18, 30),
        ),
      );

      // Create a task due at 17:00
      final taskId = await db.taskDao.insertTask(
        TasksCompanion.insert(
          title: 'Shifted Homework',
          dueDate: DateTime(2026, 10, 19, 17, 0),
          completedAt: Value(DateTime(2026, 10, 19, 16, 0)),
        ),
      );

      // Shift back by -8 hours
      final count = await tz.shiftAllEventsAndTasks(db, const Duration(hours: -8));
      expect(count, 2);

      // Verify event is now at 09:00 - 10:30
      final updatedEvent = await db.eventDao.getEventById(eventId);
      expect(updatedEvent, isNotNull);
      expect(updatedEvent!.startTime.hour, 9);
      expect(updatedEvent.startTime.minute, 0);
      expect(updatedEvent.endTime.hour, 10);
      expect(updatedEvent.endTime.minute, 30);

      // Verify task is now due at 09:00 and completed at 08:00
      final updatedTask = await db.taskDao.getTaskById(taskId);
      expect(updatedTask, isNotNull);
      expect(updatedTask!.dueDate.hour, 9);
      expect(updatedTask.dueDate.minute, 0);
      expect(updatedTask.completedAt!.hour, 8);
      expect(updatedTask.completedAt!.minute, 0);
    });
  });
}

