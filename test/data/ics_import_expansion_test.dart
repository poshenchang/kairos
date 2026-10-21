// test/data/ics_import_expansion_test.dart
//
// Imported recurring events must expand correctly through Kairos's own
// recurrence code (weekdays, EXDATE, UNTIL).

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/event_repository.dart';
import 'package:kairos/services/ics_import.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('a weekly Mon/Wed class with a skipped day and an end date', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const utc = SettingsState(timezoneMode: 'manual', manualTimezoneOffsetMinutes: 0);
    DateTime toUtcWall(DateTime t) => DateTime.utc(t.year, t.month, t.day, t.hour, t.minute, t.second);

    final parsed = parseIcs(
      [
        'BEGIN:VCALENDAR',
        'BEGIN:VEVENT',
        'UID:os-lecture',
        'DTSTART:20260907T091000Z',
        'DTEND:20260907T120000Z',
        'RRULE:FREQ=WEEKLY;BYDAY=MO,WE;UNTIL=20261031T235959Z',
        'EXDATE:20261012T091000Z',
        'SUMMARY:Operating Systems',
        'END:VEVENT',
        'END:VCALENDAR',
      ].join('\r\n'),
      fromActive: toUtcWall,
      toActive: (t) => t.toUtc(),
    );
    final e = parsed.events.single;
    await db.eventDao.insertEvent(EventsCompanion.insert(
      title: e.title,
      category: const Value('schoolwork'),
      startTime: e.startUtc,
      endTime: e.endUtc,
      isRecurring: const Value(true),
      rrule: Value(e.rrule),
    ));

    final repo = EventRepository(db.eventDao, db.holidayDao);
    final occurrences = await repo.getExpandedEventsInRange(DateTime.utc(2026, 10, 1), DateTime.utc(2026, 11, 15), utc);
    final days = occurrences.map((o) => o.startTime.toUtc().day).toList()..sort();

    // October Mondays/Wednesdays, minus the skipped Oct 12, nothing after Oct 31
    expect(days, [5, 7, 14, 19, 21, 26, 28]);
    expect(occurrences.every((o) => o.startTime.toUtc().hour == 9 && o.startTime.toUtc().minute == 10), isTrue);
  });
}
