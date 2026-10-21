// test/services/ics_import_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/services/ics_import.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  // User's active timezone for floating times: UTC+8
  DateTime fromActive(DateTime wall) =>
      DateTime.utc(wall.year, wall.month, wall.day, wall.hour, wall.minute, wall.second).subtract(const Duration(hours: 8));
  DateTime toActive(DateTime utc) {
    final w = utc.toUtc().add(const Duration(hours: 8));
    return DateTime(w.year, w.month, w.day, w.hour, w.minute, w.second);
  }

  IcsParseResult parse(String body) =>
      parseIcs('BEGIN:VCALENDAR\r\nVERSION:2.0\r\n$body\r\nEND:VCALENDAR\r\n', fromActive: fromActive, toActive: toActive);

  test('a Google-Calendar-style weekly class with TZID, location, EXDATE and an alarm', () {
    final r = parse([
      'BEGIN:VEVENT',
      'UID:abc@google.com',
      'DTSTART;TZID=Asia/Taipei:20260907T091000',
      'DTEND;TZID=Asia/Taipei:20260907T120000',
      'RRULE:FREQ=WEEKLY;WKST=SU;UNTIL=20261231T155959Z;BYDAY=MO',
      'EXDATE;TZID=Asia/Taipei:20261012T091000',
      'SUMMARY:Operating Systems\\, Lecture',
      'LOCATION:Room 103',
      'DESCRIPTION:Bring the textbook.\\nQuiz in week 4.',
      'BEGIN:VALARM',
      'ACTION:DISPLAY',
      'DESCRIPTION:Reminder',
      'TRIGGER:-PT10M',
      'END:VALARM',
      'END:VEVENT',
    ].join('\r\n'));

    final e = r.events.single;
    expect(e.title, 'Operating Systems, Lecture');
    expect(e.startUtc, DateTime.utc(2026, 9, 7, 1, 10));
    expect(e.endUtc, DateTime.utc(2026, 9, 7, 4, 0));
    expect(e.rrule, 'FREQ=WEEKLY;BYDAY=MO;UNTIL=20261231T155959Z;EXDATE=2026-10-12');
    expect(e.notes, '📍 Room 103\nBring the textbook.\nQuiz in week 4.');
    expect(r.skippedTotal, 0);
  });

  test('UTC, floating times, DURATION, and folded lines', () {
    final r = parse([
      'BEGIN:VEVENT',
      'DTSTART:20261021T020000Z',
      'DURATION:PT1H30M',
      'SUMMARY:Office hours with a very long title that the exporter folded acr',
      ' oss two lines',
      'END:VEVENT',
      'BEGIN:VEVENT',
      'DTSTART:20261022T140000',
      'DTEND:20261022T150000',
      'SUMMARY:Floating meeting',
      'END:VEVENT',
    ].join('\r\n'));

    expect(r.events[0].title, 'Office hours with a very long title that the exporter folded across two lines');
    expect(r.events[0].endUtc, DateTime.utc(2026, 10, 21, 3, 30));
    expect(r.events[1].startUtc, DateTime.utc(2026, 10, 22, 6, 0)); // 14:00 at UTC+8
  });

  test('weekly rule without BYDAY gets the start weekday', () {
    final r = parse([
      'BEGIN:VEVENT',
      'DTSTART:20261021T010000Z', // Wednesday 09:00 at UTC+8
      'DTEND:20261021T020000Z',
      'RRULE:FREQ=WEEKLY;COUNT=10',
      'SUMMARY:Lab',
      'END:VEVENT',
    ].join('\r\n'));
    expect(r.events.single.rrule, 'FREQ=WEEKLY;COUNT=10;BYDAY=WE');
  });

  test('a moved occurrence becomes a one-off and is skipped in its series', () {
    final r = parse([
      'BEGIN:VEVENT',
      'UID:series-1',
      'DTSTART:20261005T010000Z',
      'DTEND:20261005T020000Z',
      'RRULE:FREQ=WEEKLY;BYDAY=MO',
      'SUMMARY:Seminar',
      'END:VEVENT',
      'BEGIN:VEVENT',
      'UID:series-1',
      'RECURRENCE-ID:20261019T010000Z',
      'DTSTART:20261020T010000Z',
      'DTEND:20261020T020000Z',
      'SUMMARY:Seminar (moved)',
      'END:VEVENT',
    ].join('\r\n'));

    final series = r.events.firstWhere((e) => e.title == 'Seminar');
    final moved = r.events.firstWhere((e) => e.title == 'Seminar (moved)');
    expect(series.rrule, 'FREQ=WEEKLY;BYDAY=MO;EXDATE=2026-10-19');
    expect(moved.rrule, isNull);
    expect(moved.startUtc, DateTime.utc(2026, 10, 20, 1));
  });

  test('all-day, cancelled, unsupported repeats and broken events are skipped and counted', () {
    final r = parse([
      'BEGIN:VEVENT', 'DTSTART;VALUE=DATE:20261010', 'SUMMARY:Holiday', 'END:VEVENT',
      'BEGIN:VEVENT', 'DTSTART:20261021T010000Z', 'DTEND:20261021T020000Z', 'STATUS:CANCELLED', 'SUMMARY:x', 'END:VEVENT',
      'BEGIN:VEVENT', 'DTSTART:20261021T010000Z', 'DTEND:20261021T020000Z', 'RRULE:FREQ=MONTHLY', 'SUMMARY:x', 'END:VEVENT',
      'BEGIN:VEVENT', 'DTSTART:20261021T010000Z', 'DTEND:20261021T020000Z', 'RRULE:FREQ=WEEKLY;INTERVAL=2', 'SUMMARY:x', 'END:VEVENT',
      'BEGIN:VEVENT', 'DTSTART:20261021T010000Z', 'DTEND:20261021T020000Z', 'RRULE:FREQ=WEEKLY;BYDAY=1MO', 'SUMMARY:x', 'END:VEVENT',
      'BEGIN:VEVENT', 'SUMMARY:no start', 'END:VEVENT',
      'BEGIN:VEVENT', 'DTSTART:20261021T030000Z', 'DTEND:20261021T020000Z', 'SUMMARY:ends before start', 'END:VEVENT',
    ].join('\r\n'));

    expect(r.events, isEmpty);
    expect(r.skippedAllDay, 1);
    expect(r.skippedCancelled, 1);
    expect(r.skippedUnsupportedRepeat, 3);
    expect(r.skippedInvalid, 2);
  });

  test('unknown or prefixed TZIDs', () {
    final r = parse([
      'BEGIN:VEVENT',
      'DTSTART;TZID=/freeassociation.sourceforge.net/Asia/Tokyo:20261021T100000',
      'DTEND;TZID=/freeassociation.sourceforge.net/Asia/Tokyo:20261021T110000',
      'SUMMARY:Prefixed',
      'END:VEVENT',
      'BEGIN:VEVENT',
      'DTSTART;TZID=Mars/Olympus:20261021T100000',
      'DTEND;TZID=Mars/Olympus:20261021T110000',
      'SUMMARY:Unknown',
      'END:VEVENT',
    ].join('\r\n'));
    expect(r.events[0].startUtc, DateTime.utc(2026, 10, 21, 1)); // Tokyo is UTC+9
    expect(r.events[1].startUtc, DateTime.utc(2026, 10, 21, 2)); // treated as floating UTC+8
  });
}
