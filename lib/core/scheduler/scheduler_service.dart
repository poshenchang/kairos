// lib/core/scheduler/scheduler_service.dart
//
// SchedulerService — orchestrates AutoScheduler against the live database.
//
// Responsibilities:
//   1. Load all data needed by AutoScheduler from AppDatabase.
//   2. Call AutoScheduler.generateSchedule().
//   3. Delete existing auto-scheduled events for the target window.
//   4. Insert the freshly generated events.
//   5. Return the ScheduleResult (events + warnings) to the caller.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/core/scheduler/auto_scheduler.dart';
import 'package:kairos/core/scheduler/scheduler_types.dart';

/// Default do-not-schedule window: 21:00 – 09:00 (9pm to 9am).
const _defaultDoNotSchedule = [
  TimeWindow(
    start: TimeOfDay(hour: 21, minute: 0),
    end:   TimeOfDay(hour: 9,  minute: 0),
    label: 'Off-hours',
  ),
];

/// Default prep-time lookup by event type (minutes).
const _defaultPrepTypeDefaults = <String, int>{
  'lecture':     30,
  'exam':        120,
  'presentation': 60,
  'meeting':     15,
  'interview':   90,
  'gym':         10,
  'commute':     0,
};

/// How many days ahead the default scheduler looks.
const _defaultWindowDays = 7;

class SchedulerService {
  SchedulerService({
    required AppDatabase db,
    AutoScheduler? scheduler,
    List<TimeWindow>? doNotScheduleWindows,
    Map<String, int>? prepTypeDefaults,
  })  : _db = db,
        _scheduler = scheduler ?? AutoScheduler(),
        _doNotScheduleWindows =
            doNotScheduleWindows ?? _defaultDoNotSchedule,
        _prepTypeDefaults = prepTypeDefaults ?? _defaultPrepTypeDefaults;

  final AppDatabase _db;
  final AutoScheduler _scheduler;
  final List<TimeWindow> _doNotScheduleWindows;
  final Map<String, int> _prepTypeDefaults;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Run the scheduler from now through the next [_defaultWindowDays] days.
  Future<ScheduleResult> runScheduler() {
    final now = DateTime.now().toUtc();
    final end = now.add(const Duration(days: _defaultWindowDays));
    return runSchedulerForWindow(now, end);
  }

  /// Run the scheduler for an explicit [start, end] window.
  ///
  /// Steps:
  ///   1. Load fixed events, incomplete tasks, active habits, weekly completions.
  ///   2. Generate a fresh schedule via [AutoScheduler].
  ///   3. Delete existing auto-scheduled events in the window.
  ///   4. Insert the new events.
  ///   5. Return [ScheduleResult].
  Future<ScheduleResult> runSchedulerForWindow(
      DateTime start, DateTime end) async {
    // ── 1. Load data ──────────────────────────────────────────────────────

    final fixedEvents =
        await _db.eventDao.getFixedEventsInRange(start, end);

    final incompleteTasks =
        await _db.taskDao.getIncompleteTasksDueBefore(end);

    final activeHabits = await _db.habitDao.getAllActiveHabits();

    // Weekly completions: Mon 00:00 – Sun 23:59 of the week containing [start].
    final weekBounds = _currentWeekBounds(start);
    final weeklyCompletions = await _db.habitDao
        .getWeeklyCompletions(weekBounds.$1, weekBounds.$2);

    // ── 2. Generate schedule ──────────────────────────────────────────────

    final result = await _scheduler.generateSchedule(
      fixedEvents: fixedEvents,
      incompleteTasks: incompleteTasks,
      activeHabits: activeHabits,
      weeklyHabitCompletions: weeklyCompletions,
      schedulingWindowStart: start,
      schedulingWindowEnd: end,
      doNotScheduleWindows: _doNotScheduleWindows,
      prepTypeDefaults: _prepTypeDefaults,
    );

    // ── 3. Delete stale auto-scheduled events ─────────────────────────────

    await _db.eventDao.deleteAutoScheduledEventsInRange(start, end);

    // ── 4. Insert fresh events ────────────────────────────────────────────

    if (result.events.isNotEmpty) {
      await _db.eventDao.insertEvents(result.events);
    }

    return result;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Returns the (Sunday 00:00, Sunday+1 00:00) UTC bounds for the week
  /// that contains [dt].
  (DateTime, DateTime) _currentWeekBounds(DateTime dt) {
    // weekday: Mon=1, ..., Sun=7. If dt is Sunday (7), weekday % 7 is 0.
    final sunday = dt.subtract(Duration(days: dt.weekday % 7));
    final weekStart =
        DateTime.utc(sunday.year, sunday.month, sunday.day);
    final weekEnd = weekStart.add(const Duration(days: 7));
    return (weekStart, weekEnd);
  }
}
