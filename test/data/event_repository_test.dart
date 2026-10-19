// test/data/event_repository_test.dart
//
// Tests for EventRepository recurring event expansion including FREQ=DAILY,
// social events, and holiday handling.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/event_repository.dart';

Event _event({
  required int id,
  required String title,
  required String category,
  required String eventType,
  required DateTime start,
  required DateTime end,
  String? rrule,
  bool isRecurring = false,
}) {
  return Event(
    id: id,
    title: title,
    category: category,
    eventType: eventType,
    startTime: start,
    endTime: end,
    isRecurring: isRecurring,
    rrule: rrule,
    requiresPrep: false,
    prepMinutes: null,
    notes: null,
    isAutoScheduled: false,
    autoScheduleSource: null,
    isDeleted: false,
    createdAt: start,
    updatedAt: start,
  );
}

Holiday _holiday({
  required int id,
  required String name,
  required DateTime date,
  DateTime? endDate,
  String groupName = 'US Holidays',
  bool isEnabled = true,
}) {
  return Holiday(
    id: id,
    name: name,
    date: date,
    endDate: endDate,
    groupName: groupName,
    isEnabled: isEnabled,
  );
}

void main() {
  late AppDatabase db;
  late EventRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = EventRepository(db.eventDao, db.holidayDao);
  });

  tearDown(() async {
    await db.close();
  });

  group('expandRecurringEvents with FREQ=DAILY', () {
    test('expands event every single day across the window', () {
      final baseEvent = _event(
        id: 1,
        title: 'Daily Language Learning',
        category: 'personal',
        eventType: 'habit',
        start: DateTime(2026, 10, 19, 8, 0), // Monday 8:00 AM
        end: DateTime(2026, 10, 19, 8, 30),
        isRecurring: true,
        rrule: 'FREQ=DAILY',
      );

      final rangeStart = DateTime(2026, 10, 19, 0, 0);
      final rangeEnd = DateTime(2026, 10, 26, 0, 0); // 7 full days (Mon 19 through Sun 25)

      final occurrences = repository.expandRecurringEvents(baseEvent, rangeStart, rangeEnd);

      expect(occurrences.length, 7);
      for (int i = 0; i < 7; i++) {
        expect(occurrences[i].startTime.day, 19 + i);
        expect(occurrences[i].startTime.hour, 8);
        expect(occurrences[i].startTime.minute, 0);
        expect(occurrences[i].endTime.minute, 30);
      }
    });

    test('terminates after COUNT occurrences when specified', () {
      final baseEvent = _event(
        id: 2,
        title: 'Daily Podcast Sprint',
        category: 'personal',
        eventType: 'habit',
        start: DateTime(2026, 10, 19, 9, 0),
        end: DateTime(2026, 10, 19, 9, 30),
        isRecurring: true,
        rrule: 'FREQ=DAILY;COUNT=3',
      );

      final rangeStart = DateTime(2026, 10, 19, 0, 0);
      final rangeEnd = DateTime(2026, 10, 26, 0, 0);

      final occurrences = repository.expandRecurringEvents(baseEvent, rangeStart, rangeEnd);

      expect(occurrences.length, 3);
    });

    test('personal daily habits continue during holidays while lectures are blacked out', () {
      final holiday = _holiday(
        id: 1,
        name: 'Fall Break',
        date: DateTime(2026, 10, 21), // Wednesday
      );

      final lecture = _event(
        id: 10,
        title: 'Algorithms Lecture',
        category: 'schoolwork',
        eventType: 'lecture',
        start: DateTime(2026, 10, 19, 10, 0),
        end: DateTime(2026, 10, 19, 11, 30),
        isRecurring: true,
        rrule: 'FREQ=WEEKLY;BYDAY=MO,WE,FR',
      );

      final dailyHabit = _event(
        id: 11,
        title: 'Duolingo Spanish',
        category: 'personal',
        eventType: 'habit',
        start: DateTime(2026, 10, 19, 8, 0),
        end: DateTime(2026, 10, 19, 8, 20),
        isRecurring: true,
        rrule: 'FREQ=DAILY',
      );

      final rangeStart = DateTime(2026, 10, 19, 0, 0);
      final rangeEnd = DateTime(2026, 10, 24, 0, 0); // Mon 19 to Fri 23 (5 full days)

      final lectureOccurrences = repository.expandRecurringEvents(
        lecture,
        rangeStart,
        rangeEnd,
        holidays: [holiday],
      );

      // Mon, Wed, Fri -> Wednesday is holiday -> only Mon and Fri
      expect(lectureOccurrences.length, 2);
      expect(lectureOccurrences.any((e) => e.startTime.day == 21), isFalse);

      final habitOccurrences = repository.expandRecurringEvents(
        dailyHabit,
        rangeStart,
        rangeEnd,
        holidays: [holiday],
      );

      // Daily personal habit continues all 5 days including the holiday!
      expect(habitOccurrences.length, 5);
      expect(habitOccurrences.any((e) => e.startTime.day == 21), isTrue);
    });

    test('HolidayDao toggleHolidayGroup toggles only targeted group', () async {
      await db.holidayDao.seedDefaultHolidays(2026);
      final all = await db.holidayDao.getAllHolidays();
      expect(all.any((h) => h.groupName == 'Taiwanese Holidays'), isTrue);
      expect(all.any((h) => h.groupName == 'US Holidays'), isTrue);

      // Disable all US holidays
      await db.holidayDao.toggleHolidayGroup('US Holidays', false);
      final updated = await db.holidayDao.getAllHolidays();

      final usHolidays = updated.where((h) => h.groupName == 'US Holidays');
      final twHolidays = updated.where((h) => h.groupName == 'Taiwanese Holidays');

      for (final h in usHolidays) {
        expect(h.isEnabled, isFalse);
      }
      for (final h in twHolidays) {
        expect(h.isEnabled, isTrue); // Taiwanese holidays remain active
      }
    });
    test('does not generate occurrences before the base event start date', () {
      // Event starts on Oct 27, 2026 (Tuesday).
      // Range starts on Oct 19, 2026. The Tuesday before Oct 27 is Oct 20.
      final baseEvent = _event(
        id: 20,
        title: 'Algorithms Advanced',
        category: 'schoolwork',
        eventType: 'lecture',
        start: DateTime(2026, 10, 27, 14, 0),
        end: DateTime(2026, 10, 27, 16, 0),
        isRecurring: true,
        rrule: 'FREQ=WEEKLY;BYDAY=TU',
      );

      final rangeStart = DateTime(2026, 10, 19, 0, 0);
      final rangeEnd = DateTime(2026, 11, 10, 0, 0); // Spans Oct 20, Oct 27, Nov 3

      final occurrences = repository.expandRecurringEvents(baseEvent, rangeStart, rangeEnd);

      // Oct 20 MUST NOT be present because it is before baseEvent.startTime!
      expect(occurrences.any((e) => e.startTime.day == 20 && e.startTime.month == 10), isFalse);
      // Oct 27 and Nov 3 MUST be present
      expect(occurrences.any((e) => e.startTime.day == 27 && e.startTime.month == 10), isTrue);
      expect(occurrences.any((e) => e.startTime.day == 3 && e.startTime.month == 11), isTrue);
      expect(occurrences.length, 2);
    });

    test('EXDATE skips cancelled occurrence dates during expansion', () {
      final baseEvent = _event(
        id: 21,
        title: 'Weekly Seminar',
        category: 'schoolwork',
        eventType: 'lecture',
        start: DateTime(2026, 10, 20, 10, 0),
        end: DateTime(2026, 10, 20, 11, 30),
        isRecurring: true,
        rrule: 'FREQ=WEEKLY;BYDAY=TU;EXDATE=2026-10-27',
      );

      final rangeStart = DateTime(2026, 10, 19, 0, 0);
      final rangeEnd = DateTime(2026, 11, 10, 0, 0); // Oct 20, 27, Nov 3

      final occurrences = repository.expandRecurringEvents(baseEvent, rangeStart, rangeEnd);

      expect(occurrences.length, 2);
      expect(occurrences.any((e) => e.startTime.day == 20), isTrue);
      expect(occurrences.any((e) => e.startTime.day == 27), isFalse); // cancelled!
      expect(occurrences.any((e) => e.startTime.day == 3), isTrue);
    });

    test('cancelRecurringOccurrence and restoreRecurringOccurrence update EXDATE in database', () async {
      final eventId = await db.eventDao.insertEvent(EventsCompanion.insert(
        title: 'Weekly Yoga',
        category: const Value('health'),
        eventType: const Value('habit'),
        startTime: DateTime(2026, 10, 19, 7, 0),
        endTime: DateTime(2026, 10, 19, 8, 0),
        isRecurring: const Value(true),
        rrule: const Value('FREQ=WEEKLY;BYDAY=MO'),
      ));

      // Cancel Oct 26 occurrence
      await repository.cancelRecurringOccurrence(eventId, DateTime(2026, 10, 26));

      var fetched = await db.eventDao.getEventById(eventId);
      expect(fetched!.rrule, contains('EXDATE=2026-10-26'));

      // Restore Oct 26 occurrence
      await repository.restoreRecurringOccurrence(eventId, '2026-10-26');
      fetched = await db.eventDao.getEventById(eventId);
      expect(fetched!.rrule, isNot(contains('2026-10-26')));
    });

    test('Holidays repeat annually matching month and day across years', () {
      // Holiday defined with year 2024
      final holiday = _holiday(
        id: 99,
        name: 'New Year Day',
        date: DateTime(2024, 1, 1),
      );

      final recurringLecture = _event(
        id: 30,
        title: 'Monday Class',
        category: 'schoolwork',
        eventType: 'lecture',
        start: DateTime(2029, 1, 1, 9, 0), // 2029 Jan 1 is Monday!
        end: DateTime(2029, 1, 1, 10, 0),
        isRecurring: true,
        rrule: 'FREQ=WEEKLY;BYDAY=MO',
      );

      final occurrences = repository.expandRecurringEvents(
        recurringLecture,
        DateTime(2029, 1, 1, 0, 0),
        DateTime(2029, 1, 2, 0, 0),
        holidays: [holiday],
      );

      // Should be blacked out because Jan 1 matches annually!
      expect(occurrences.isEmpty, isTrue);
    });
  });
}

