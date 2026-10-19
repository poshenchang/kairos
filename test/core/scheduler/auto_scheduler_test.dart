// test/core/scheduler/auto_scheduler_test.dart
//
// Unit tests for AutoScheduler.
//
// Run with: flutter test test/core/scheduler/auto_scheduler_test.dart
//
// These tests use only plain Dart — no Flutter widgets, no database.
// EventsCompanion / Event / Task / Habit are Drift-generated; we use
// lightweight fakes that match the field signatures.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' show Value;

import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/core/scheduler/auto_scheduler.dart';
import 'package:kairos/core/scheduler/scheduler_types.dart';

// ── Helpers ────────────────────────────────────────────────────────────────

/// Monday 09:00 UTC (a workday morning).
DateTime _mon(int hour, [int minute = 0]) =>
    DateTime.utc(2024, 1, 8, hour, minute); // 2024-01-08 is a Monday

Event _event({
  required int id,
  required DateTime start,
  required DateTime end,
  bool requiresPrep = false,
  int? prepMinutes,
  String? eventType,
  String title = 'Event',
}) =>
    Event(
      id: id,
      title: title,
      category: 'work',
      eventType: eventType,
      startTime: start,
      endTime: end,
      isRecurring: false,
      rrule: null,
      requiresPrep: requiresPrep,
      prepMinutes: prepMinutes,
      isAutoScheduled: false,
      autoScheduleSource: null,
      notes: null,
      isDeleted: false,
      createdAt: start,
      updatedAt: start,
    );

Habit _habit({
  required int id,
  required String title,
  int targetFrequencyPerWeek = 3,
  int minSessionMinutes = 30,
  int maxSessionMinutes = 60,
  String preferredWindow = 'any',
  String daysFilter = 'all',
}) =>
    Habit(
      id: id,
      title: title,
      category: 'personal',
      description: null,
      targetFrequencyPerWeek: targetFrequencyPerWeek,
      minSessionMinutes: minSessionMinutes,
      maxSessionMinutes: maxSessionMinutes,
      preferredWindow: preferredWindow,
      daysFilter: daysFilter,
      isActive: true,
      isDeleted: false,
      createdAt: DateTime.utc(2024, 1, 1),
      updatedAt: DateTime.utc(2024, 1, 1),
    );

// ── Tests ──────────────────────────────────────────────────────────────────

void main() {
  late AutoScheduler scheduler;

  setUp(() => scheduler = AutoScheduler());

  // ── FreeSlot tests ──────────────────────────────────────────────────────

  group('FreeSlot', () {
    test('duration is correct', () {
      final slot = FreeSlot(
        start: _mon(9),
        end: _mon(11),
      );
      expect(slot.duration, const Duration(hours: 2));
    });

    test('isUsable rejects slots < 30 min', () {
      final slot = FreeSlot(start: _mon(9), end: _mon(9, 20));
      expect(slot.isUsable(), isFalse);
    });

    test('isUsable accepts slots ≥ 30 min', () {
      final slot = FreeSlot(start: _mon(9), end: _mon(9, 30));
      expect(slot.isUsable(), isTrue);
    });

    test('splitAt produces correct halves', () {
      final slot = FreeSlot(start: _mon(9), end: _mon(11));
      final (before, after) = slot.splitAt(_mon(10));
      expect(before.start, _mon(9));
      expect(before.end, _mon(10));
      expect(after.start, _mon(10));
      expect(after.end, _mon(11));
    });
  });

  // ── TimeWindow tests ────────────────────────────────────────────────────

  group('TimeWindow.contains', () {
    test('normal window — inside', () {
      expect(TimeWindow.morning.contains(_mon(9)), isTrue);
    });

    test('normal window — outside (before)', () {
      expect(TimeWindow.morning.contains(_mon(5)), isFalse);
    });

    test('normal window — outside (after)', () {
      expect(TimeWindow.morning.contains(_mon(13)), isFalse);
    });

    test('midnight-wrapping overnight window — late night inside', () {
      final midnight = DateTime.utc(2024, 1, 8, 23, 30);
      expect(TimeWindow.overnight.contains(midnight), isTrue);
    });

    test('midnight-wrapping overnight window — early morning inside', () {
      final earlyMorning = DateTime.utc(2024, 1, 9, 5, 0);
      expect(TimeWindow.overnight.contains(earlyMorning), isTrue);
    });

    test('midnight-wrapping overnight window — afternoon outside', () {
      expect(TimeWindow.overnight.contains(_mon(14)), isFalse);
    });
  });

  // ── generateSchedule — free slot building ──────────────────────────────

  group('generateSchedule — free slots', () {
    test('returns empty when entire window is occupied', () async {
      final start = _mon(9);
      final end = _mon(17);
      final blockingEvent = _event(id: 1, start: start, end: end);

      final result = await scheduler.generateSchedule(
        fixedEvents: [blockingEvent],
        incompleteTasks: [],
        activeHabits: [],
        weeklyHabitCompletions: {},
        schedulingWindowStart: start,
        schedulingWindowEnd: end,
        doNotScheduleWindows: [],
        prepTypeDefaults: {},
      );

      expect(result.events, isEmpty);
    });

    test('doNotScheduleWindow blocks overnight hours', () async {
      // Window: Mon 00:00 – Mon 23:59.
      final start = DateTime.utc(2024, 1, 8, 0, 0);
      final end = DateTime.utc(2024, 1, 8, 23, 59);

      final result = await scheduler.generateSchedule(
        fixedEvents: [],
        incompleteTasks: [],
        activeHabits: [
          _habit(id: 1, title: 'Run', targetFrequencyPerWeek: 1,
              minSessionMinutes: 30, maxSessionMinutes: 60,
              preferredWindow: 'any'),
        ],
        weeklyHabitCompletions: {},
        schedulingWindowStart: start,
        schedulingWindowEnd: end,
        doNotScheduleWindows: [TimeWindow.overnight], // 22:00–08:00
        prepTypeDefaults: {},
      );

      // All scheduled sessions must start after 08:00 and before 22:00.
      for (final e in result.events) {
        final sessionStart = e.startTime.value!;
        expect(sessionStart.hour >= 8 && sessionStart.hour < 22, isTrue,
            reason: 'Session at ${sessionStart.hour}:00 violates overnight block');
      }
    });
  });

  // ── generateSchedule — prep blocks ────────────────────────────────────

  group('generateSchedule — prep blocks', () {
    test('schedules prep before event with requiresPrep=true', () async {
      // Window: Mon 08:00 – 18:00.
      // Event at 14:00–16:00 needs 60 min prep.
      final winStart = _mon(8);
      final winEnd = _mon(18);
      final event = _event(
        id: 1,
        start: _mon(14),
        end: _mon(16),
        requiresPrep: true,
        prepMinutes: 60,
        title: 'Big Meeting',
      );

      final result = await scheduler.generateSchedule(
        fixedEvents: [event],
        incompleteTasks: [],
        activeHabits: [],
        weeklyHabitCompletions: {},
        schedulingWindowStart: winStart,
        schedulingWindowEnd: winEnd,
        doNotScheduleWindows: [],
        prepTypeDefaults: {},
      );

      final prepEvents =
          result.events.where((e) => e.title.value!.startsWith('Prep:')).toList();
      expect(prepEvents, isNotEmpty);
      // All prep blocks must end before the event starts.
      for (final p in prepEvents) {
        expect(p.endTime.value!.isBefore(event.startTime) ||
                p.endTime.value! == event.startTime,
            isTrue,
            reason: 'Prep block ends after event starts');
      }
      // Total prep scheduled should be ~60 min.
      final totalMin = prepEvents.fold<int>(
        0,
        (sum, e) =>
            sum + e.endTime.value!.difference(e.startTime.value!).inMinutes,
      );
      expect(totalMin, greaterThanOrEqualTo(30));
    });

    test('emits insufficientPrepTime warning when no slots available', () async {
      // Event fills the entire window.
      final winStart = _mon(9);
      final winEnd = _mon(10);
      final event = _event(
        id: 1,
        start: _mon(9),
        end: _mon(10),
        requiresPrep: true,
        prepMinutes: 60,
        title: 'Back-to-back',
      );

      final result = await scheduler.generateSchedule(
        fixedEvents: [event],
        incompleteTasks: [],
        activeHabits: [],
        weeklyHabitCompletions: {},
        schedulingWindowStart: winStart,
        schedulingWindowEnd: winEnd,
        doNotScheduleWindows: [],
        prepTypeDefaults: {},
      );

      expect(
        result.warnings
            .any((w) => w.type == SchedulerWarningType.insufficientPrepTime),
        isTrue,
      );
    });

    test('uses prepTypeDefaults when event.prepMinutes is null', () async {
      final winStart = _mon(8);
      final winEnd = _mon(18);
      final event = _event(
        id: 2,
        start: _mon(15),
        end: _mon(17),
        requiresPrep: true,
        prepMinutes: null,
        eventType: 'exam',
        title: 'Final Exam',
      );

      final result = await scheduler.generateSchedule(
        fixedEvents: [event],
        incompleteTasks: [],
        activeHabits: [],
        weeklyHabitCompletions: {},
        schedulingWindowStart: winStart,
        schedulingWindowEnd: winEnd,
        doNotScheduleWindows: [],
        prepTypeDefaults: {'exam': 120},
      );

      final prepEvents =
          result.events.where((e) => e.title.value!.startsWith('Prep:')).toList();
      expect(prepEvents, isNotEmpty);
    });
  });

  // ── generateSchedule — habit sessions ──────────────────────────────────

  group('generateSchedule — habit sessions', () {
    test('schedules the correct number of sessions', () async {
      final winStart = _mon(8);
      final winEnd = _mon(20);
      final habit = _habit(
        id: 1,
        title: 'Meditate',
        targetFrequencyPerWeek: 3,
        minSessionMinutes: 20,
        maxSessionMinutes: 30,
        preferredWindow: 'any',
      );

      final result = await scheduler.generateSchedule(
        fixedEvents: [],
        incompleteTasks: [],
        activeHabits: [habit],
        weeklyHabitCompletions: {1: 1}, // 1 done → 2 remaining
        schedulingWindowStart: winStart,
        schedulingWindowEnd: winEnd,
        doNotScheduleWindows: [],
        prepTypeDefaults: {},
      );

      final habitEvents = result.events
          .where((e) => e.autoScheduleSource.value == 'habit:1')
          .toList();
      expect(habitEvents.length, 2);
    });

    test('respects maxSessionMinutes', () async {
      final winStart = _mon(8);
      final winEnd = _mon(20);
      final habit = _habit(
        id: 1,
        title: 'Run',
        targetFrequencyPerWeek: 1,
        minSessionMinutes: 30,
        maxSessionMinutes: 45,
        preferredWindow: 'any',
      );

      final result = await scheduler.generateSchedule(
        fixedEvents: [],
        incompleteTasks: [],
        activeHabits: [habit],
        weeklyHabitCompletions: {},
        schedulingWindowStart: winStart,
        schedulingWindowEnd: winEnd,
        doNotScheduleWindows: [],
        prepTypeDefaults: {},
      );

      for (final e in result.events) {
        final dur =
            e.endTime.value!.difference(e.startTime.value!).inMinutes;
        expect(dur, lessThanOrEqualTo(45));
      }
    });

    test('prefers morning slots for morning habit', () async {
      // Window Mon 06:00–22:00.
      final winStart = _mon(6);
      final winEnd = _mon(22);

      // Block out morning with an event so only afternoon is free.
      final morningBlock = _event(id: 99, start: _mon(6), end: _mon(12));

      final habit = _habit(
        id: 1,
        title: 'Yoga',
        targetFrequencyPerWeek: 1,
        preferredWindow: 'morning',
        minSessionMinutes: 30,
        maxSessionMinutes: 60,
      );

      final result = await scheduler.generateSchedule(
        fixedEvents: [morningBlock],
        incompleteTasks: [],
        activeHabits: [habit],
        weeklyHabitCompletions: {},
        schedulingWindowStart: winStart,
        schedulingWindowEnd: winEnd,
        doNotScheduleWindows: [],
        prepTypeDefaults: {},
      );

      // Morning is blocked → should fall back to afternoon.
      final habitEvents = result.events
          .where((e) => e.autoScheduleSource.value == 'habit:1')
          .toList();
      expect(habitEvents, isNotEmpty);
      // Since morning is blocked, session must start ≥ 12:00.
      final sessionHour = habitEvents.first.startTime.value!.hour;
      expect(sessionHour, greaterThanOrEqualTo(12));
    });

    test('emits noSlotsForHabit warning when window is full', () async {
      final winStart = _mon(9);
      final winEnd = _mon(10);
      // Block entire window.
      final block = _event(id: 1, start: _mon(9), end: _mon(10));

      final habit = _habit(id: 1, title: 'Swim', targetFrequencyPerWeek: 2);

      final result = await scheduler.generateSchedule(
        fixedEvents: [block],
        incompleteTasks: [],
        activeHabits: [habit],
        weeklyHabitCompletions: {},
        schedulingWindowStart: winStart,
        schedulingWindowEnd: winEnd,
        doNotScheduleWindows: [],
        prepTypeDefaults: {},
      );

      expect(
        result.warnings
            .any((w) => w.type == SchedulerWarningType.noSlotsForHabit),
        isTrue,
      );
    });

    test('skips habits already at target completions', () async {
      final winStart = _mon(9);
      final winEnd = _mon(17);
      final habit = _habit(id: 1, title: 'Done', targetFrequencyPerWeek: 2);

      final result = await scheduler.generateSchedule(
        fixedEvents: [],
        incompleteTasks: [],
        activeHabits: [habit],
        weeklyHabitCompletions: {1: 2}, // already done
        schedulingWindowStart: winStart,
        schedulingWindowEnd: winEnd,
        doNotScheduleWindows: [],
        prepTypeDefaults: {},
      );

      final habitEvents = result.events
          .where((e) => e.autoScheduleSource.value == 'habit:1')
          .toList();
      expect(habitEvents, isEmpty);
    });
  });

  // ── isAutoScheduled flag ────────────────────────────────────────────────

  group('generated events', () {
    test('all generated events have isAutoScheduled=true', () async {
      final habit = _habit(id: 1, title: 'Read', targetFrequencyPerWeek: 1);

      final result = await scheduler.generateSchedule(
        fixedEvents: [],
        incompleteTasks: [],
        activeHabits: [habit],
        weeklyHabitCompletions: {},
        schedulingWindowStart: _mon(8),
        schedulingWindowEnd: _mon(20),
        doNotScheduleWindows: [],
        prepTypeDefaults: {},
      );

      for (final e in result.events) {
        expect(e.isAutoScheduled.value, isTrue);
      }
    });

    group('habit daysFilter', () {
      test('schedules weekdays-only habit exclusively on Mon-Fri', () async {
        final winStart = _mon(8);
        final winEnd = DateTime.utc(2024, 1, 21, 22, 0);
        final habit = _habit(
          id: 1,
          title: 'Code Study',
          targetFrequencyPerWeek: 3,
          daysFilter: 'weekdays',
        );

        final result = await scheduler.generateSchedule(
          fixedEvents: [],
          incompleteTasks: [],
          activeHabits: [habit],
          weeklyHabitCompletions: {},
          schedulingWindowStart: winStart,
          schedulingWindowEnd: winEnd,
          doNotScheduleWindows: [],
          prepTypeDefaults: {},
        );

        final habitEvents = result.events
            .where((e) => e.autoScheduleSource.value == 'habit:1')
            .toList();

        expect(habitEvents, isNotEmpty);
        for (final e in habitEvents) {
          final weekday = e.startTime.value.toLocal().weekday;
          expect(weekday, inInclusiveRange(DateTime.monday, DateTime.friday));
        }
      });

      test('schedules weekends-only habit exclusively on Sat-Sun', () async {
        final winStart = _mon(8);
        final winEnd = DateTime.utc(2024, 1, 21, 22, 0);
        final habit = _habit(
          id: 2,
          title: 'Weekend Hike',
          targetFrequencyPerWeek: 2,
          daysFilter: 'weekends',
        );

        final result = await scheduler.generateSchedule(
          fixedEvents: [],
          incompleteTasks: [],
          activeHabits: [habit],
          weeklyHabitCompletions: {},
          schedulingWindowStart: winStart,
          schedulingWindowEnd: winEnd,
          doNotScheduleWindows: [TimeWindow.overnight],
          prepTypeDefaults: {},
        );

        final habitEvents = result.events
            .where((e) => e.autoScheduleSource.value == 'habit:2')
            .toList();

        expect(habitEvents, isNotEmpty);
        for (final e in habitEvents) {
          final weekday = e.startTime.value.toLocal().weekday;
          expect(weekday, inInclusiveRange(DateTime.saturday, DateTime.sunday));
        }
      });
    });

    group('time constraints & even habit distribution', () {
      test('strictly schedules starting at integer o\'clock (:00) or half past (:30)', () async {
        final winStart = DateTime.utc(2024, 1, 8, 9, 13);
        final winEnd = DateTime.utc(2024, 1, 8, 17, 47);
        final event = _event(
          id: 1,
          start: DateTime.utc(2024, 1, 8, 14, 25),
          end: DateTime.utc(2024, 1, 8, 15, 45),
          requiresPrep: true,
          prepMinutes: 60,
        );
        final habit = _habit(
          id: 1,
          title: 'Daily Reading',
          targetFrequencyPerWeek: 1,
          minSessionMinutes: 30,
          maxSessionMinutes: 60,
        );

        final result = await scheduler.generateSchedule(
          fixedEvents: [event],
          incompleteTasks: [],
          activeHabits: [habit],
          weeklyHabitCompletions: {},
          schedulingWindowStart: winStart,
          schedulingWindowEnd: winEnd,
          doNotScheduleWindows: [],
          prepTypeDefaults: {},
        );

        expect(result.events, isNotEmpty);
        for (final e in result.events) {
          final start = e.startTime.value!;
          expect(start.minute == 0 || start.minute == 30, isTrue,
              reason: 'Event ${e.title.value} starts at ${start.hour}:${start.minute}, which is not :00 or :30');
          expect(start.second, 0);
          expect(start.millisecond, 0);
        }
      });

      test('prefers 9am to 9pm (09:00 - 21:00) when scheduling', () async {
        final winStart = DateTime.utc(2024, 1, 8, 6, 0);
        final winEnd = DateTime.utc(2024, 1, 8, 23, 0);
        final habit = _habit(
          id: 1,
          title: 'Morning Yoga',
          targetFrequencyPerWeek: 1,
          minSessionMinutes: 30,
          maxSessionMinutes: 60,
          preferredWindow: 'any',
        );

        final result = await scheduler.generateSchedule(
          fixedEvents: [],
          incompleteTasks: [],
          activeHabits: [habit],
          weeklyHabitCompletions: {},
          schedulingWindowStart: winStart,
          schedulingWindowEnd: winEnd,
          doNotScheduleWindows: [],
          prepTypeDefaults: {},
        );

        expect(result.events, isNotEmpty);
        for (final e in result.events) {
          final start = e.startTime.value!;
          final end = e.endTime.value!;
          expect(start.hour >= 9, isTrue, reason: 'Event scheduled before 9am: $start');
          expect(end.hour < 21 || (end.hour == 21 && end.minute == 0), isTrue,
              reason: 'Event scheduled after 9pm: $end');
        }
      });

      test('schedules with at least 30-minute buffer apart from fixed events when possible', () async {
        final winStart = _mon(9);
        final winEnd = _mon(18);
        final fixed = _event(
          id: 10,
          start: _mon(11),
          end: _mon(12),
        );
        final habit = _habit(
          id: 1,
          title: 'Deep Work',
          targetFrequencyPerWeek: 1,
          minSessionMinutes: 30,
          maxSessionMinutes: 60,
          preferredWindow: 'any',
        );

        final result = await scheduler.generateSchedule(
          fixedEvents: [fixed],
          incompleteTasks: [],
          activeHabits: [habit],
          weeklyHabitCompletions: {},
          schedulingWindowStart: winStart,
          schedulingWindowEnd: winEnd,
          doNotScheduleWindows: [],
          prepTypeDefaults: {},
        );

        final habitEvent = result.events.firstWhere((e) => e.autoScheduleSource.value == 'habit:1');
        final hStart = habitEvent.startTime.value!;
        final hEnd = habitEvent.endTime.value!;

        if (!hEnd.isAfter(fixed.startTime)) {
          expect(fixed.startTime.difference(hEnd).inMinutes >= 30, isTrue);
        } else if (!hStart.isBefore(fixed.endTime)) {
          expect(hStart.difference(fixed.endTime).inMinutes >= 30, isTrue);
        }
      });

      test('distributes habit sessions evenly across the week and avoids heavy hard-event days', () async {
        final winStart = DateTime.utc(2024, 1, 8, 9, 0);
        final winEnd = DateTime.utc(2024, 1, 14, 21, 0);

        final monHard = _event(id: 101, start: DateTime.utc(2024, 1, 8, 10, 0), end: DateTime.utc(2024, 1, 8, 16, 0));
        final wedHard = _event(id: 102, start: DateTime.utc(2024, 1, 10, 10, 0), end: DateTime.utc(2024, 1, 10, 16, 0));

        final habit = _habit(
          id: 1,
          title: 'Guitar Practice',
          targetFrequencyPerWeek: 2,
          minSessionMinutes: 30,
          maxSessionMinutes: 60,
        );

        final result = await scheduler.generateSchedule(
          fixedEvents: [monHard, wedHard],
          incompleteTasks: [],
          activeHabits: [habit],
          weeklyHabitCompletions: {},
          schedulingWindowStart: winStart,
          schedulingWindowEnd: winEnd,
          doNotScheduleWindows: [TimeWindow.overnight],
          prepTypeDefaults: {},
        );

        final habitEvents = result.events.where((e) => e.autoScheduleSource.value == 'habit:1').toList();
        expect(habitEvents.length, 2);

        final scheduledDays = habitEvents.map((e) => e.startTime.value!.day).toList();
        expect(scheduledDays.contains(8), isFalse, reason: 'Avoided heavy Monday');
        expect(scheduledDays.contains(10), isFalse, reason: 'Avoided heavy Wednesday');
        expect(scheduledDays[0] != scheduledDays[1], isTrue, reason: 'Sessions are on different days');
      });
    });
  });
}
