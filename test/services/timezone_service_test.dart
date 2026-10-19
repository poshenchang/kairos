// test/services/timezone_service_test.dart
//
// Tests for TimezoneService: active timezone conversions, dynamic timetable shifting,
// UTC cloud serialization, and schedule shift repair.

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/timezone_service.dart';

void main() {
  group('TimezoneService - Active Timezone Transformations & Dynamic Display', () {
    final tz = TimezoneService.instance;

    const tpeSettings = SettingsState(
      timezoneMode: 'manual',
      manualTimezoneOffsetMinutes: 480, // UTC+8 (Taipei / Beijing / Singapore)
      manualTimezoneName: 'UTC+08:00 (Taipei, CST)',
    );

    const tokyoSettings = SettingsState(
      timezoneMode: 'manual',
      manualTimezoneOffsetMinutes: 540, // UTC+9 (Tokyo / Seoul)
      manualTimezoneName: 'UTC+09:00 (Tokyo, JST)',
    );

    const londonSettings = SettingsState(
      timezoneMode: 'manual',
      manualTimezoneOffsetMinutes: 0, // UTC+0 (London / GMT)
      manualTimezoneName: 'UTC+00:00 (London, GMT)',
    );

    const nySettings = SettingsState(
      timezoneMode: 'manual',
      manualTimezoneOffsetMinutes: -300, // UTC-5 (New York, EST)
      manualTimezoneName: 'UTC-05:00 (New York, EST)',
    );

    test('toActiveTime dynamically shifts display time across different timezones', () {
      // Ground-truth event at 01:00:00 UTC
      final utcEvent = DateTime.utc(2026, 10, 19, 1, 0);

      // In Taipei (UTC+8): 9:00 AM
      final tpeDisplay = tz.toActiveTime(utcEvent, tpeSettings);
      expect(tpeDisplay.day, 19);
      expect(tpeDisplay.hour, 9);
      expect(tpeDisplay.minute, 0);

      // In Tokyo (UTC+9): 10:00 AM
      final tokyoDisplay = tz.toActiveTime(utcEvent, tokyoSettings);
      expect(tokyoDisplay.day, 19);
      expect(tokyoDisplay.hour, 10);
      expect(tokyoDisplay.minute, 0);

      // In London (UTC+0): 1:00 AM
      final londonDisplay = tz.toActiveTime(utcEvent, londonSettings);
      expect(londonDisplay.day, 19);
      expect(londonDisplay.hour, 1);
      expect(londonDisplay.minute, 0);

      // In New York (UTC-5): 8:00 PM previous day (Oct 18)
      final nyDisplay = tz.toActiveTime(utcEvent, nySettings);
      expect(nyDisplay.day, 18);
      expect(nyDisplay.hour, 20);
      expect(nyDisplay.minute, 0);
    });

    test('fromActiveTime converts local user input into ground-truth UTC', () {
      // User in Taipei enters an event at 9:00 AM on Oct 19
      final userSelectedTime = DateTime(2026, 10, 19, 9, 0);
      final utcResult = tz.fromActiveTime(userSelectedTime, tpeSettings);

      expect(utcResult.isUtc, isTrue);
      expect(utcResult.day, 19);
      expect(utcResult.hour, 1);
      expect(utcResult.minute, 0);

      // Round-trip verification: toActiveTime(fromActiveTime(x)) == x
      final roundTrip = tz.toActiveTime(utcResult, tpeSettings);
      expect(roundTrip.year, userSelectedTime.year);
      expect(roundTrip.month, userSelectedTime.month);
      expect(roundTrip.day, userSelectedTime.day);
      expect(roundTrip.hour, userSelectedTime.hour);
      expect(roundTrip.minute, userSelectedTime.minute);
    });

    test('formatForRemoteSync and parseRemoteTimestamp preserve exact UTC moments', () {
      final utcInstant = DateTime.utc(2026, 10, 19, 1, 30);
      final formatted = tz.formatForRemoteSync(utcInstant);
      expect(formatted, contains('2026-10-19T01:30:00'));

      final parsed = tz.parseRemoteTimestamp(formatted);
      expect(parsed.isUtc, isTrue);
      expect(parsed.year, 2026);
      expect(parsed.month, 10);
      expect(parsed.day, 19);
      expect(parsed.hour, 1);
      expect(parsed.minute, 30);

      // Verify handling of Postgres "+00" with space
      final postgresStyle = tz.parseRemoteTimestamp('2026-10-19 01:30:00+00');
      expect(postgresStyle.isUtc, isTrue);
      expect(postgresStyle.hour, 1);

      // Verify handling of no timezone indicator (forces UTC)
      final noTz = tz.parseRemoteTimestamp('2026-10-19T01:30:00');
      expect(noTz.isUtc, isTrue);
      expect(noTz.hour, 1);

      // Verify handling of +08:00 offset
      final offsetStyle = tz.parseRemoteTimestamp('2026-10-19T09:30:00+08:00');
      expect(offsetStyle.isUtc, isTrue);
      expect(offsetStyle.hour, 1);
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
          startTime: DateTime.utc(2026, 10, 19, 17, 0),
          endTime: DateTime.utc(2026, 10, 19, 18, 30),
        ),
      );

      // Create a task due at 17:00
      final taskId = await db.taskDao.insertTask(
        TasksCompanion.insert(
          title: 'Shifted Homework',
          dueDate: DateTime.utc(2026, 10, 19, 17, 0),
          completedAt: Value(DateTime.utc(2026, 10, 19, 16, 0)),
        ),
      );

      // Shift back by -8 hours
      final count = await tz.shiftAllEventsAndTasks(db, const Duration(hours: -8));
      expect(count, 2);

      // Verify event is now at 09:00 - 10:30 UTC
      final updatedEvent = await db.eventDao.getEventById(eventId);
      expect(updatedEvent, isNotNull);
      expect(updatedEvent!.startTime.toUtc().hour, 9);
      expect(updatedEvent.startTime.toUtc().minute, 0);
      expect(updatedEvent.endTime.toUtc().hour, 10);
      expect(updatedEvent.endTime.toUtc().minute, 30);

      // Verify task is now due at 09:00 and completed at 08:00 UTC
      final updatedTask = await db.taskDao.getTaskById(taskId);
      expect(updatedTask, isNotNull);
      expect(updatedTask!.dueDate.toUtc().hour, 9);
      expect(updatedTask.dueDate.toUtc().minute, 0);
      expect(updatedTask.completedAt!.toUtc().hour, 8);
      expect(updatedTask.completedAt!.toUtc().minute, 0);
    });
  });
}
