// lib/core/scheduler/auto_scheduler.dart
//
// AutoScheduler — fills free calendar time with prep blocks and habit sessions.
//
// Algorithm overview
// ──────────────────
// Phase 0 – Build free slots
//   Scan the scheduling window minute-by-minute (logically), subtracting:
//     • All fixed (non-auto-scheduled) event occupancies
//     • All doNotScheduleWindows (applied daily)
//   Keep only slots ≥ 30 minutes.
//
// Phase 1 – Prep blocks
//   For each fixed event with requiresPrep=true:
//     1. Determine total prep minutes (event.prepMinutes ?? prepTypeDefaults[eventType] ?? 60).
//     2. Find all free slots that end before the event starts.
//     3. Distribute prep in sessions of 30–90 min across those slots,
//        starting from the nearest slot and spreading backward.
//     4. If < 50 % of ideal prep time can be satisfied → emit SchedulerWarning.
//     5. Mark consumed portions of slots as used.
//
// Phase 2 – Habit sessions
//   For each active habit (sorted by remaining sessions desc):
//     1. Calculate remaining = targetFrequencyPerWeek - weeklyCompletions[id].
//     2. Resolve preferredWindow → TimeWindow.
//     3. For each remaining session needed, pick the best available free slot:
//          a. First try slots that fall within the preferredWindow.
//          b. Fall back to any slot if none preferred available.
//     4. Clamp session length to [minSessionMinutes, maxSessionMinutes].
//     5. Consume the front of the slot; if remaining slot is still ≥ 30 min,
//        leave it available for later habits.
//     6. If no slot found for a session → emit SchedulerWarning.
//
// Phase 3 – Build EventsCompanion list and return ScheduleResult.

import 'package:drift/drift.dart' show Value;
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/core/scheduler/scheduler_types.dart';

/// Stateless, pure-Dart scheduling engine.
///
/// Has no Flutter or database dependencies — all data is passed in.
/// Designed to be easily unit-tested.
class AutoScheduler {
  // ── Constants ──────────────────────────────────────────────────────────────

  static const Duration _minSlotDuration = Duration(minutes: 30);
  static const Duration _minPrepSession = Duration(minutes: 30);
  static const Duration _maxPrepSession = Duration(minutes: 90);

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Generate a fresh auto-schedule for the given window.
  ///
  /// Parameters
  /// ----------
  /// [fixedEvents]              Existing non-auto-scheduled events.
  /// [incompleteTasks]          Tasks with upcoming deadlines (reserved for
  ///                             future task-block scheduling; not used in v1).
  /// [activeHabits]             Habits the scheduler should create sessions for.
  /// [weeklyHabitCompletions]   habitId → sessions already completed this week.
  /// [schedulingWindowStart]    Inclusive start of the window to fill.
  /// [schedulingWindowEnd]      Exclusive end of the window to fill.
  /// [doNotScheduleWindows]     Daily time ranges in which no event may be placed.
  /// [prepTypeDefaults]         eventType → default prep minutes.
  Future<ScheduleResult> generateSchedule({
    required List<Event> fixedEvents,
    required List<Task> incompleteTasks,
    required List<Habit> activeHabits,
    required Map<int, int> weeklyHabitCompletions,
    required DateTime schedulingWindowStart,
    required DateTime schedulingWindowEnd,
    required List<TimeWindow> doNotScheduleWindows,
    required Map<String, int> prepTypeDefaults,
  }) async {
    final warnings = <SchedulerWarning>[];
    final companions = <EventsCompanion>[];

    // ── Phase 0: Build initial free-slot list ─────────────────────────────

    final freeSlots = _buildFreeSlots(
      windowStart: schedulingWindowStart,
      windowEnd: schedulingWindowEnd,
      fixedEvents: fixedEvents,
      doNotScheduleWindows: doNotScheduleWindows,
    );

    // Track occupied spans to evaluate buffer spacing between events.
    final occupiedSpans = <_OccupiedSpan>[
      for (final e in fixedEvents) _OccupiedSpan(e.startTime, e.endTime),
    ];
    final dailyHardLoads = _computeDailyLoads(fixedEvents);
    final dailyAutoLoads = <DateTime, int>{};

    // ── Phase 1: Prep blocks ──────────────────────────────────────────────

    // Sort events by start time so we process nearest preps first.
    final prepEvents = fixedEvents
        .where((e) => e.requiresPrep)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    for (final event in prepEvents) {
      final prepResult = _schedulePrepBlocks(
        event: event,
        freeSlots: freeSlots,
        prepTypeDefaults: prepTypeDefaults,
        occupiedSpans: occupiedSpans,
        dailyHardLoads: dailyHardLoads,
        dailyAutoLoads: dailyAutoLoads,
      );
      companions.addAll(prepResult.companions);
      if (prepResult.warning != null) warnings.add(prepResult.warning!);
    }

    // ── Phase 2: Habit sessions ───────────────────────────────────────────

    // Process habits with the most remaining sessions first (greedy priority).
    final sortedHabits = List<Habit>.from(activeHabits)
      ..sort((a, b) {
        final remainA = _remaining(a, weeklyHabitCompletions);
        final remainB = _remaining(b, weeklyHabitCompletions);
        return remainB.compareTo(remainA);
      });

    for (final habit in sortedHabits) {
      final needed = _remaining(habit, weeklyHabitCompletions);
      if (needed <= 0) continue;

      final habitResult = _scheduleHabitSessions(
        habit: habit,
        sessionsNeeded: needed,
        freeSlots: freeSlots,
        windowStart: schedulingWindowStart,
        occupiedSpans: occupiedSpans,
        dailyHardLoads: dailyHardLoads,
        dailyAutoLoads: dailyAutoLoads,
      );
      companions.addAll(habitResult.companions);
      if (habitResult.warning != null) warnings.add(habitResult.warning!);
    }

    return ScheduleResult(events: companions, warnings: warnings);
  }

  // ── Phase 0 helpers ────────────────────────────────────────────────────────

  /// Build the initial list of [FreeSlot]s by scanning [windowStart, windowEnd]
  /// and removing all fixed-event occupancies and blocked windows.
  List<FreeSlot> _buildFreeSlots({
    required DateTime windowStart,
    required DateTime windowEnd,
    required List<Event> fixedEvents,
    required List<TimeWindow> doNotScheduleWindows,
  }) {
    // Start with the entire scheduling window as one big free slot.
    final slots = <FreeSlot>[FreeSlot(start: windowStart, end: windowEnd)];

    // Subtract every fixed event.
    for (final event in fixedEvents) {
      _subtractInterval(slots, event.startTime, event.endTime);
    }

    // Subtract doNotSchedule windows (applied to each calendar day).
    if (doNotScheduleWindows.isNotEmpty) {
      final days = _daysInRange(windowStart, windowEnd);
      for (final day in days) {
        for (final window in doNotScheduleWindows) {
          final sMinutes = window.start.hour * 60 + window.start.minute;
          final eMinutes = window.end.hour * 60 + window.end.minute;

          final isUtc = day.isUtc;
          if (eMinutes > sMinutes) {
            // Normal daytime window (e.g. 12:00 – 13:00)
            final bStart = isUtc
                ? DateTime.utc(day.year, day.month, day.day,
                    window.start.hour, window.start.minute)
                : DateTime(day.year, day.month, day.day,
                    window.start.hour, window.start.minute);
            final bEnd = isUtc
                ? DateTime.utc(day.year, day.month, day.day,
                    window.end.hour, window.end.minute)
                : DateTime(day.year, day.month, day.day,
                    window.end.hour, window.end.minute);
            _clampAndSubtract(slots, bStart, bEnd, windowStart, windowEnd);
          } else {
            // Midnight-wrapping window (e.g. 22:00 – 08:00 overnight)
            // 1. Early morning block on [day]: 00:00 to window.end
            final mStart = isUtc
                ? DateTime.utc(day.year, day.month, day.day, 0, 0)
                : DateTime(day.year, day.month, day.day, 0, 0);
            final mEnd = isUtc
                ? DateTime.utc(day.year, day.month, day.day,
                    window.end.hour, window.end.minute)
                : DateTime(day.year, day.month, day.day,
                    window.end.hour, window.end.minute);
            _clampAndSubtract(slots, mStart, mEnd, windowStart, windowEnd);

            // 2. Late night block on [day]: window.start to midnight (next day 00:00)
            final nStart = isUtc
                ? DateTime.utc(day.year, day.month, day.day,
                    window.start.hour, window.start.minute)
                : DateTime(day.year, day.month, day.day,
                    window.start.hour, window.start.minute);
            final nEnd = (isUtc
                    ? DateTime.utc(day.year, day.month, day.day, 0, 0)
                    : DateTime(day.year, day.month, day.day, 0, 0))
                .add(const Duration(days: 1));
            _clampAndSubtract(slots, nStart, nEnd, windowStart, windowEnd);
          }
        }
      }
    }

    // Remove slots that are too short to be useful.
    slots.removeWhere((s) => !s.isUsable(minimum: _minSlotDuration));
    return slots;
  }

  void _clampAndSubtract(List<FreeSlot> slots, DateTime start, DateTime end,
      DateTime windowStart, DateTime windowEnd) {
    var bStart = start;
    var bEnd = end;
    if (bEnd.isBefore(windowStart) || bStart.isAfter(windowEnd)) return;
    if (bStart.isBefore(windowStart)) bStart = windowStart;
    if (bEnd.isAfter(windowEnd)) bEnd = windowEnd;
    if (bStart.isBefore(bEnd)) {
      _subtractInterval(slots, bStart, bEnd);
    }
  }

  /// Remove the interval [removeStart, removeEnd] from [slots] in-place.
  void _subtractInterval(
      List<FreeSlot> slots, DateTime removeStart, DateTime removeEnd) {
    for (int i = slots.length - 1; i >= 0; i--) {
      final slot = slots[i];
      if (removeEnd.isBefore(slot.start) ||
          !removeStart.isBefore(slot.end)) {
        // No overlap.
        continue;
      }

      slots.removeAt(i);
      int insertIdx = i;

      // Portion before the removed interval.
      if (removeStart.isAfter(slot.start)) {
        final before = FreeSlot(start: slot.start, end: removeStart);
        if (before.duration > Duration.zero) {
          slots.insert(insertIdx, before);
          insertIdx++;
        }
      }

      // Portion after the removed interval.
      if (removeEnd.isBefore(slot.end)) {
        final after = FreeSlot(start: removeEnd, end: slot.end);
        if (after.duration > Duration.zero) {
          slots.insert(insertIdx, after);
        }
      }
    }
  }

  /// Return a list of calendar days that overlap [start, end].
  List<DateTime> _daysInRange(DateTime start, DateTime end) {
    final days = <DateTime>[];
    final isUtc = start.isUtc;
    var current = isUtc
        ? DateTime.utc(start.year, start.month, start.day)
        : DateTime(start.year, start.month, start.day);
    final last = isUtc
        ? DateTime.utc(end.year, end.month, end.day)
        : DateTime(end.year, end.month, end.day);
    while (!current.isAfter(last)) {
      days.add(current);
      current = current.add(const Duration(days: 1));
    }
    return days;
  }

  // ── Phase 1 helpers ────────────────────────────────────────────────────────

  _PrepResult _schedulePrepBlocks({
    required Event event,
    required List<FreeSlot> freeSlots,
    required Map<String, int> prepTypeDefaults,
    required List<_OccupiedSpan> occupiedSpans,
    required Map<DateTime, int> dailyHardLoads,
    required Map<DateTime, int> dailyAutoLoads,
  }) {
    final companions = <EventsCompanion>[];

    // Determine total prep time needed.
    final totalPrepMinutes = event.prepMinutes ??
        (event.eventType != null
            ? prepTypeDefaults[event.eventType!]
            : null) ??
        60; // ultimate fallback: 60 min

    final sessionCount =
        (totalPrepMinutes / _maxPrepSession.inMinutes).ceil().clamp(1, 5);
    int targetPerSession =
        (totalPrepMinutes / sessionCount).round().clamp(
              _minPrepSession.inMinutes,
              _maxPrepSession.inMinutes,
            );
    targetPerSession = ((targetPerSession / 30).round() * 30).clamp(30, 90);

    int scheduledMinutes = 0;

    while (scheduledMinutes < totalPrepMinutes) {
      final remaining = totalPrepMinutes - scheduledMinutes;
      int sessionMin = remaining < _minPrepSession.inMinutes ? _minPrepSession.inMinutes : remaining;
      if (sessionMin > targetPerSession) sessionMin = targetPerSession;
      sessionMin = ((sessionMin / 30).round() * 30).clamp(30, 90);
      final sessionDuration = Duration(minutes: sessionMin);

      _CandidateSlot? bestCandidate;
      double bestScore = -999999.0;

      for (final slot in freeSlots) {
        if (!slot.start.isBefore(event.startTime)) continue;
        final effectiveEnd = slot.end.isAfter(event.startTime) ? event.startTime : slot.end;
        if (effectiveEnd.difference(slot.start) < sessionDuration) continue;

        final firstCand = _alignForwardToHalfHour(slot.start);
        var cand = firstCand;
        while (!cand.add(sessionDuration).isAfter(effectiveEnd)) {
          final candEnd = cand.add(sessionDuration);
          final dayKey = DateTime.utc(cand.year, cand.month, cand.day);

          double score = 0.0;

          // 1. Daytime preference (9am - 9pm)
          if (_isWithin9amTo9pm(cand, candEnd)) {
            score += 3000.0;
          } else {
            score -= 1000.0;
          }

          // 2. Buffer from other events
          if (_has30MinBuffer(cand, candEnd, occupiedSpans)) {
            score += 1500.0;
          }

          // 3. Buffer before target event (at least 30 min)
          if (event.startTime.difference(candEnd) >= const Duration(minutes: 30)) {
            score += 1000.0;
          }

          // 4. Proximity to event: closer is better
          final hoursBefore = event.startTime.difference(candEnd).inHours;
          if (hoursBefore >= 0 && hoursBefore <= 48) {
            score += (48 - hoursBefore) * 20.0;
          } else if (hoursBefore > 48) {
            score -= (hoursBefore - 48) * 10.0;
          }

          // 5. Daily load
          final hardMin = dailyHardLoads[dayKey] ?? 0;
          final autoMin = dailyAutoLoads[dayKey] ?? 0;
          score -= (hardMin + autoMin) * 1.0;

          if (score > bestScore) {
            bestScore = score;
            bestCandidate = _CandidateSlot(start: cand, end: candEnd, slot: slot);
          }

          cand = cand.add(const Duration(minutes: 30));
        }
      }

      // Fallback: If no candidate was found for sessionDuration, try fallback with _minPrepSession
      if (bestCandidate == null && sessionDuration > _minPrepSession) {
        final fallbackDuration = _minPrepSession;
        for (final slot in freeSlots) {
          if (!slot.start.isBefore(event.startTime)) continue;
          final effectiveEnd = slot.end.isAfter(event.startTime) ? event.startTime : slot.end;
          if (effectiveEnd.difference(slot.start) < fallbackDuration) continue;

          final firstCand = _alignForwardToHalfHour(slot.start);
          var cand = firstCand;
          while (!cand.add(fallbackDuration).isAfter(effectiveEnd)) {
            final candEnd = cand.add(fallbackDuration);
            bestCandidate = _CandidateSlot(start: cand, end: candEnd, slot: slot);
            break;
          }
          if (bestCandidate != null) break;
        }
      }

      if (bestCandidate == null) break;

      final sessionStart = bestCandidate.start;
      final sessionEnd = bestCandidate.end;
      final actualMin = sessionEnd.difference(sessionStart).inMinutes;

      companions.add(_buildEventCompanion(
        title: 'Prep: ${event.title}',
        category: event.category,
        eventType: 'prep',
        start: sessionStart,
        end: sessionEnd,
        source: 'prep:${event.id}',
        notes: 'Auto-scheduled prep block for "${event.title}".',
      ));

      scheduledMinutes += actualMin;
      occupiedSpans.add(_OccupiedSpan(sessionStart, sessionEnd));
      final dayKey = DateTime.utc(sessionStart.year, sessionStart.month, sessionStart.day);
      dailyAutoLoads[dayKey] = (dailyAutoLoads[dayKey] ?? 0) + actualMin;

      _subtractInterval(freeSlots, sessionStart, sessionEnd);
      freeSlots.removeWhere((s) => !s.isUsable(minimum: _minSlotDuration));
    }

    SchedulerWarning? warning;
    if (scheduledMinutes < totalPrepMinutes * 0.5) {
      warning = SchedulerWarning(
        message: 'Only $scheduledMinutes of $totalPrepMinutes prep minutes '
            'could be scheduled for "${event.title}" '
            '(${(scheduledMinutes / totalPrepMinutes * 100).round()}% of ideal).',
        type: SchedulerWarningType.insufficientPrepTime,
      );
    }

    return _PrepResult(companions: companions, warning: warning);
  }

  // ── Phase 2 helpers ────────────────────────────────────────────────────────

  _HabitResult _scheduleHabitSessions({
    required Habit habit,
    required int sessionsNeeded,
    required List<FreeSlot> freeSlots,
    required DateTime windowStart,
    required List<_OccupiedSpan> occupiedSpans,
    required Map<DateTime, int> dailyHardLoads,
    required Map<DateTime, int> dailyAutoLoads,
  }) {
    final companions = <EventsCompanion>[];
    int scheduledSessions = 0;

    final preferredWindow =
        TimeWindow.fromHabitPreference(habit.preferredWindow);
    final minDuration = Duration(minutes: habit.minSessionMinutes);
    final maxDuration = Duration(minutes: habit.maxSessionMinutes);

    final targetDuration = maxDuration >= _minSlotDuration ? maxDuration : minDuration;
    final scheduledDatesForHabit = <DateTime>{};

    for (int s = 0; s < sessionsNeeded; s++) {
      _CandidateSlot? bestCandidate;
      double bestScore = -999999.0;

      for (final slot in freeSlots) {
        if (!slot.isUsable(minimum: minDuration)) continue;

        final candDuration = slot.duration >= targetDuration ? targetDuration : slot.duration;
        if (candDuration < minDuration) continue;

        final firstCand = _alignForwardToHalfHour(slot.start);
        var cand = firstCand;

        while (!cand.add(candDuration).isAfter(slot.end)) {
          final candEnd = cand.add(candDuration);
          final localStart = cand.toLocal();

          if (habit.daysFilter == 'weekdays' && localStart.weekday > 5) {
            cand = cand.add(const Duration(minutes: 30));
            continue;
          }
          if (habit.daysFilter == 'weekends' && localStart.weekday < 6) {
            cand = cand.add(const Duration(minutes: 30));
            continue;
          }

          final dayKey = DateTime.utc(cand.year, cand.month, cand.day);

          double score = 0.0;

          // 1. Daytime preference (9am - 9pm)
          final isDaytime = _isWithin9amTo9pm(cand, candEnd);
          if (isDaytime) {
            score += 3000.0;
          } else {
            score -= 1000.0;
          }

          // 2. 30-min buffer preference
          final hasBuffer = _has30MinBuffer(cand, candEnd, occupiedSpans);
          if (hasBuffer) {
            score += 1500.0;
          }

          // 3. Preferred window
          if (preferredWindow.contains(cand)) {
            score += 800.0;
          }

          // 4. Daily load (hard events load + already scheduled auto events)
          final hardMin = dailyHardLoads[dayKey] ?? 0;
          final autoMin = dailyAutoLoads[dayKey] ?? 0;
          score -= (hardMin + autoMin) * 1.5;

          // 5. Habit distribution across the week
          if (scheduledDatesForHabit.contains(dayKey)) {
            score -= 8000.0;
          } else if (scheduledDatesForHabit.isNotEmpty) {
            int minDiffDays = 999;
            for (final d in scheduledDatesForHabit) {
              final diff = (cand.difference(d).inDays).abs();
              if (diff < minDiffDays) minDiffDays = diff;
            }
            if (minDiffDays == 1) {
              score -= 300.0;
            } else if (minDiffDays >= 2) {
              score += 500.0;
            }
          }

          // 6. Chronological tie-breaker
          score -= cand.difference(windowStart).inHours * 0.1;

          if (score > bestScore) {
            bestScore = score;
            bestCandidate = _CandidateSlot(start: cand, end: candEnd, slot: slot);
          }

          cand = cand.add(const Duration(minutes: 30));
        }
      }

      if (bestCandidate == null) break;

      final sessionStart = bestCandidate.start;
      final sessionEnd = bestCandidate.end;

      final dayKey = DateTime.utc(sessionStart.year, sessionStart.month, sessionStart.day);
      scheduledDatesForHabit.add(dayKey);

      companions.add(_buildEventCompanion(
        title: habit.title,
        category: habit.category,
        eventType: 'habit_session',
        start: sessionStart,
        end: sessionEnd,
        source: 'habit:${habit.id}',
        notes: 'Auto-scheduled ${habit.title} session.',
      ));

      scheduledSessions++;
      occupiedSpans.add(_OccupiedSpan(sessionStart, sessionEnd));
      dailyAutoLoads[dayKey] = (dailyAutoLoads[dayKey] ?? 0) + sessionEnd.difference(sessionStart).inMinutes;

      _subtractInterval(freeSlots, sessionStart, sessionEnd);
      freeSlots.removeWhere((s) => !s.isUsable(minimum: _minSlotDuration));
    }

    SchedulerWarning? warning;
    if (scheduledSessions < sessionsNeeded) {
      warning = SchedulerWarning(
        message: 'Could only schedule $scheduledSessions of $sessionsNeeded '
            'remaining "${habit.title}" sessions this week — no free slots found.',
        type: SchedulerWarningType.noSlotsForHabit,
      );
    }

    return _HabitResult(companions: companions, warning: warning);
  }

  // ── Scheduling Engine Helpers ──────────────────────────────────────────────

  static DateTime _alignForwardToHalfHour(DateTime dt) {
    final isUtc = dt.isUtc;
    if (dt.second == 0 && dt.millisecond == 0 && (dt.minute == 0 || dt.minute == 30)) {
      return dt;
    }
    if (dt.minute < 30) {
      return isUtc
          ? DateTime.utc(dt.year, dt.month, dt.day, dt.hour, 30)
          : DateTime(dt.year, dt.month, dt.day, dt.hour, 30);
    } else {
      return isUtc
          ? DateTime.utc(dt.year, dt.month, dt.day, dt.hour + 1, 0)
          : DateTime(dt.year, dt.month, dt.day, dt.hour + 1, 0);
    }
  }

  static bool _isWithin9amTo9pm(DateTime start, DateTime end) {
    if (start.year != end.year || start.month != end.month || start.day != end.day) {
      return false;
    }
    final sMinutes = start.hour * 60 + start.minute;
    final eMinutes = end.hour * 60 + end.minute;
    return sMinutes >= 540 && eMinutes <= 1260;
  }

  static bool _has30MinBuffer(DateTime start, DateTime end, List<_OccupiedSpan> occupiedSpans) {
    for (final span in occupiedSpans) {
      if (start.isBefore(span.end) && end.isAfter(span.start)) {
        return false;
      }
      if (!span.end.isAfter(start)) {
        if (start.difference(span.end) < const Duration(minutes: 30)) {
          return false;
        }
      }
      if (!span.start.isBefore(end)) {
        if (span.start.difference(end) < const Duration(minutes: 30)) {
          return false;
        }
      }
    }
    return true;
  }

  static Map<DateTime, int> _computeDailyLoads(List<Event> fixedEvents) {
    final loads = <DateTime, int>{};
    for (final e in fixedEvents) {
      final dayKey = DateTime.utc(e.startTime.year, e.startTime.month, e.startTime.day);
      final dur = e.endTime.difference(e.startTime).inMinutes;
      loads[dayKey] = (loads[dayKey] ?? 0) + dur;
    }
    return loads;
  }


  // ── Companion factory ──────────────────────────────────────────────────────

  EventsCompanion _buildEventCompanion({
    required String title,
    required String category,
    required String eventType,
    required DateTime start,
    required DateTime end,
    required String source,
    String? notes,
  }) {
    final now = DateTime.now().toUtc();
    return EventsCompanion(
      title: Value(title),
      category: Value(category),
      eventType: Value(eventType),
      startTime: Value(start.toUtc()),
      endTime: Value(end.toUtc()),
      isRecurring: const Value(false),
      requiresPrep: const Value(false),
      isAutoScheduled: const Value(true),
      autoScheduleSource: Value(source),
      notes: Value(notes),
      isDeleted: const Value(false),
      createdAt: Value(now),
      updatedAt: Value(now),
    );
  }

  // ── Utilities ──────────────────────────────────────────────────────────────

  int _remaining(Habit habit, Map<int, int> weeklyCompletions) {
    final done = weeklyCompletions[habit.id] ?? 0;
    return (habit.targetFrequencyPerWeek - done).clamp(0, 99);
  }
}

// ── Internal result types (private to this file) ───────────────────────────

class _PrepResult {
  const _PrepResult({required this.companions, this.warning});
  final List<EventsCompanion> companions;
  final SchedulerWarning? warning;
}

class _HabitResult {
  const _HabitResult({required this.companions, this.warning});
  final List<EventsCompanion> companions;
  final SchedulerWarning? warning;
}

class _OccupiedSpan {
  final DateTime start;
  final DateTime end;
  const _OccupiedSpan(this.start, this.end);
}

class _CandidateSlot {
  final DateTime start;
  final DateTime end;
  final FreeSlot slot;
  const _CandidateSlot({required this.start, required this.end, required this.slot});
}
