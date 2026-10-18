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

    // ── Phase 1: Prep blocks ──────────────────────────────────────────────

    // Sort events by start time so we process nearest preps last (greedy).
    final prepEvents = fixedEvents
        .where((e) => e.requiresPrep)
        .toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    for (final event in prepEvents) {
      final prepResult = _schedulePrepBlocks(
        event: event,
        freeSlots: freeSlots,
        prepTypeDefaults: prepTypeDefaults,
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
          final (blockStart, blockEnd) =
              _windowToDateRange(window, day, windowStart, windowEnd);
          if (blockStart != null && blockEnd != null) {
            _subtractInterval(slots, blockStart, blockEnd);
          }
        }
      }
    }

    // Remove slots that are too short to be useful.
    slots.removeWhere((s) => !s.isUsable(minimum: _minSlotDuration));
    return slots;
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

      // Portion before the removed interval.
      if (removeStart.isAfter(slot.start)) {
        final before = FreeSlot(start: slot.start, end: removeStart);
        if (before.duration > Duration.zero) slots.insert(i, before);
      }

      // Portion after the removed interval.
      if (removeEnd.isBefore(slot.end)) {
        final after = FreeSlot(start: removeEnd, end: slot.end);
        if (after.duration > Duration.zero) slots.insert(i + 1, after);
      }
    }
  }

  /// Convert a [TimeWindow] into concrete [DateTime] bounds for a given [day].
  ///
  /// Handles windows that wrap past midnight (e.g. 22:00 – 08:00 on the same
  /// logical day becomes two intervals: [22:00 – midnight] and [midnight – 08:00]).
  /// For simplicity we produce the block that falls on [day]; the midnight-wrap
  /// portion on the preceding day is handled when we process that day.
  (DateTime?, DateTime?) _windowToDateRange(
      TimeWindow window, DateTime day, DateTime windowStart, DateTime windowEnd) {
    final sMinutes = window.start.hour * 60 + window.start.minute;
    final eMinutes = window.end.hour * 60 + window.end.minute;

    DateTime blockStart, blockEnd;

    if (eMinutes > sMinutes) {
      // Normal window (e.g. 08:00 – 22:00).
      blockStart = DateTime(day.year, day.month, day.day,
          window.start.hour, window.start.minute);
      blockEnd = DateTime(day.year, day.month, day.day,
          window.end.hour, window.end.minute);
    } else {
      // Wraps midnight: e.g. 22:00 on [day] through 08:00 on [day+1].
      blockStart = DateTime(day.year, day.month, day.day,
          window.start.hour, window.start.minute);
      blockEnd = DateTime(day.year, day.month, day.day,
          window.end.hour, window.end.minute)
          .add(const Duration(days: 1));
    }

    // Clamp to the overall scheduling window.
    if (blockEnd.isBefore(windowStart) || blockStart.isAfter(windowEnd)) {
      return (null, null);
    }
    if (blockStart.isBefore(windowStart)) blockStart = windowStart;
    if (blockEnd.isAfter(windowEnd)) blockEnd = windowEnd;
    if (!blockStart.isBefore(blockEnd)) return (null, null);

    return (blockStart, blockEnd);
  }

  /// Return a list of calendar days (midnight UTC) that overlap [start, end].
  List<DateTime> _daysInRange(DateTime start, DateTime end) {
    final days = <DateTime>[];
    var current = DateTime(start.year, start.month, start.day);
    final last = DateTime(end.year, end.month, end.day);
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
  }) {
    final companions = <EventsCompanion>[];

    // Determine total prep time needed.
    final totalPrepMinutes = event.prepMinutes ??
        (event.eventType != null
            ? prepTypeDefaults[event.eventType!]
            : null) ??
        60; // ultimate fallback: 60 min

    final totalPrepDuration = Duration(minutes: totalPrepMinutes);

    // Collect free slots that end ≤ event start.
    final availableSlots = freeSlots
        .where((s) => !s.end.isAfter(event.startTime))
        .toList()
      ..sort((a, b) => b.start.compareTo(a.start)); // nearest first

    if (availableSlots.isEmpty) {
      return _PrepResult(
        companions: [],
        warning: SchedulerWarning(
          message: 'No free time found before "${event.title}" to schedule '
              'prep blocks (needed $totalPrepMinutes min).',
          type: SchedulerWarningType.insufficientPrepTime,
        ),
      );
    }

    // Determine ideal number of sessions and target per-session length.
    final sessionCount =
        (totalPrepMinutes / _maxPrepSession.inMinutes).ceil().clamp(1, 5);
    final targetPerSession =
        (totalPrepMinutes / sessionCount).round().clamp(
              _minPrepSession.inMinutes,
              _maxPrepSession.inMinutes,
            );

    int scheduledMinutes = 0;
    int sessionsScheduled = 0;

    // Distribute sessions across available slots (nearest-first greedy).
    for (final slot in availableSlots) {
      if (scheduledMinutes >= totalPrepMinutes) break;

      final remaining = totalPrepMinutes - scheduledMinutes;
      final sessionMin =
          remaining.clamp(_minPrepSession.inMinutes, targetPerSession);
      final sessionDuration = Duration(minutes: sessionMin);

      if (slot.duration < sessionDuration) {
        // Slot is too small for a full session — use what's available if ≥ 30 min.
        if (slot.duration < _minPrepSession) continue;
      }

      final actualDuration =
          slot.duration < sessionDuration ? slot.duration : sessionDuration;
      final sessionStart = slot.end.subtract(actualDuration); // pack to end
      final sessionEnd = slot.end;

      companions.add(_buildEventCompanion(
        title: 'Prep: ${event.title}',
        category: event.category,
        eventType: 'prep',
        start: sessionStart,
        end: sessionEnd,
        source: 'prep:${event.id}',
        notes: 'Auto-scheduled prep block for "${event.title}".',
      ));

      scheduledMinutes += actualDuration.inMinutes;
      sessionsScheduled++;

      // Consume the used portion from the slot in-place.
      _consumeSlotEnd(freeSlots, slot, sessionStart);
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

  /// Remove the portion [consumedStart, slot.end] from [slot] in [freeSlots].
  void _consumeSlotEnd(
      List<FreeSlot> freeSlots, FreeSlot slot, DateTime consumedStart) {
    final idx = freeSlots.indexOf(slot);
    if (idx == -1) return;

    if (consumedStart.isAfter(slot.start)) {
      // Leave the portion before consumedStart.
      freeSlots[idx] = FreeSlot(start: slot.start, end: consumedStart);
      if (!freeSlots[idx].isUsable(minimum: _minSlotDuration)) {
        freeSlots.removeAt(idx);
      }
    } else {
      // The entire slot is consumed.
      freeSlots.removeAt(idx);
    }
  }

  // ── Phase 2 helpers ────────────────────────────────────────────────────────

  _HabitResult _scheduleHabitSessions({
    required Habit habit,
    required int sessionsNeeded,
    required List<FreeSlot> freeSlots,
  }) {
    final companions = <EventsCompanion>[];
    int scheduledSessions = 0;

    final preferredWindow =
        TimeWindow.fromHabitPreference(habit.preferredWindow);
    final minDuration = Duration(minutes: habit.minSessionMinutes);
    final maxDuration = Duration(minutes: habit.maxSessionMinutes);

    for (int s = 0; s < sessionsNeeded; s++) {
      // Try preferred window first, then any slot.
      FreeSlot? picked = _pickSlotForHabit(
        freeSlots: freeSlots,
        preferredWindow: preferredWindow,
        minDuration: minDuration,
        preferPreferred: true,
      );
      picked ??= _pickSlotForHabit(
        freeSlots: freeSlots,
        preferredWindow: preferredWindow,
        minDuration: minDuration,
        preferPreferred: false,
      );

      if (picked == null) break; // no more free slots anywhere

      // Clamp session length.
      final sessionDuration =
          picked.duration > maxDuration ? maxDuration : picked.duration;
      final sessionStart = picked.start;
      final sessionEnd = sessionStart.add(sessionDuration);

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

      // Shrink or remove the consumed slot.
      _consumeSlotFront(freeSlots, picked, sessionDuration);
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

  /// Return the best free slot for a habit session.
  ///
  /// If [preferPreferred] is true, only considers slots that start inside
  /// [preferredWindow]. Otherwise considers all slots.
  FreeSlot? _pickSlotForHabit({
    required List<FreeSlot> freeSlots,
    required TimeWindow preferredWindow,
    required Duration minDuration,
    required bool preferPreferred,
  }) {
    final candidates = freeSlots.where((s) {
      if (!s.isUsable(minimum: minDuration)) return false;
      if (preferPreferred && !preferredWindow.contains(s.start)) return false;
      return true;
    }).toList();

    if (candidates.isEmpty) return null;

    // Among candidates, pick the earliest start to fill days left-to-right.
    candidates.sort((a, b) => a.start.compareTo(b.start));
    return candidates.first;
  }

  /// Consume [consumed] from the front of [slot] in [freeSlots].
  void _consumeSlotFront(
      List<FreeSlot> freeSlots, FreeSlot slot, Duration consumed) {
    final idx = freeSlots.indexOf(slot);
    if (idx == -1) return;

    final newStart = slot.start.add(consumed);
    if (!newStart.isBefore(slot.end)) {
      freeSlots.removeAt(idx);
    } else {
      final remainder = FreeSlot(start: newStart, end: slot.end);
      if (remainder.isUsable(minimum: _minSlotDuration)) {
        freeSlots[idx] = remainder;
      } else {
        freeSlots.removeAt(idx);
      }
    }
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
