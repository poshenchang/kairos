// lib/core/scheduler/scheduler_types.dart
//
// Supporting types used by AutoScheduler and SchedulerService.

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:kairos/data/database/app_database.dart';

// ── FreeSlot ──────────────────────────────────────────────────────────────────

/// A contiguous window of unoccupied time available for scheduling.
class FreeSlot {
  FreeSlot({required this.start, required this.end})
      : assert(!end.isBefore(start), 'FreeSlot end must be ≥ start');

  DateTime start;
  DateTime end;

  Duration get duration => end.difference(start);

  /// Whether this slot is long enough to be useful (≥ [minimum]).
  bool isUsable({Duration minimum = const Duration(minutes: 30)}) =>
      duration >= minimum;

  /// Split this slot at [at], returning the two resulting slots.
  /// The original slot is consumed — callers should replace it in their list.
  (FreeSlot before, FreeSlot after) splitAt(DateTime at) {
    assert(at.isAfter(start) && at.isBefore(end));
    return (
      FreeSlot(start: start, end: at),
      FreeSlot(start: at, end: end),
    );
  }

  /// Consume [consumed] from the front of this slot, shrinking it.
  /// Returns null if the slot is fully consumed.
  FreeSlot? consumeFromStart(Duration consumed) {
    final newStart = start.add(consumed);
    if (!newStart.isBefore(end)) return null;
    return FreeSlot(start: newStart, end: end);
  }

  @override
  String toString() =>
      'FreeSlot(${start.toIso8601String()} – ${end.toIso8601String()}, '
      '${duration.inMinutes} min)';
}

// ── TimeWindow ────────────────────────────────────────────────────────────────

/// A recurrent daily window during which scheduling is blocked or preferred.
///
/// Used for:
/// - `doNotScheduleWindows`: windows where the scheduler must not place events.
/// - `preferredWindow`: resolved from [Habit.preferredWindow] to prefer certain
///   time-of-day slots.
class TimeWindow {
  const TimeWindow({
    required this.start,
    required this.end,
    this.label = '',
  });

  final TimeOfDay start;
  final TimeOfDay end;

  /// Human-readable name, e.g. "Sleep", "Morning", "Work hours".
  final String label;

  /// Returns the well-known preferred windows for habits.
  static const TimeWindow morning =
      TimeWindow(start: TimeOfDay(hour: 6, minute: 0),
                 end:   TimeOfDay(hour: 12, minute: 0),
                 label: 'morning');

  static const TimeWindow afternoon =
      TimeWindow(start: TimeOfDay(hour: 12, minute: 0),
                 end:   TimeOfDay(hour: 17, minute: 0),
                 label: 'afternoon');

  static const TimeWindow evening =
      TimeWindow(start: TimeOfDay(hour: 17, minute: 0),
                 end:   TimeOfDay(hour: 22, minute: 0),
                 label: 'evening');

  /// Default do-not-schedule window: 22:00 – 08:00 (overnight).
  static const TimeWindow overnight =
      TimeWindow(start: TimeOfDay(hour: 22, minute: 0),
                 end:   TimeOfDay(hour: 8, minute: 0),
                 label: 'Sleep');

  /// Whether a given [DateTime] falls within this window on its calendar day.
  ///
  /// Handles windows that wrap past midnight (e.g. 22:00 – 08:00).
  bool contains(DateTime dt) {
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    final dtMinutes = dt.hour * 60 + dt.minute;

    if (endMinutes > startMinutes) {
      // Normal window: e.g. 06:00 – 12:00
      return dtMinutes >= startMinutes && dtMinutes < endMinutes;
    } else {
      // Wraps midnight: e.g. 22:00 – 08:00
      return dtMinutes >= startMinutes || dtMinutes < endMinutes;
    }
  }

  /// Resolve the [Habit.preferredWindow] string to a [TimeWindow].
  static TimeWindow fromHabitPreference(String pref) => switch (pref) {
        'morning'   => morning,
        'afternoon' => afternoon,
        'evening'   => evening,
        _           => const TimeWindow(
            start: TimeOfDay(hour: 0, minute: 0),
            end:   TimeOfDay(hour: 23, minute: 59),
            label: 'any',
          ),
      };

  @override
  String toString() =>
      'TimeWindow($label: ${start.hour}:${_pad(start.minute)} – '
      '${end.hour}:${_pad(end.minute)})';

  static String _pad(int n) => n.toString().padLeft(2, '0');
}

// ── SchedulerWarning ──────────────────────────────────────────────────────────

enum SchedulerWarningType {
  /// Less than 50 % of the ideal prep time could be scheduled.
  insufficientPrepTime,

  /// No suitable free slot was found for a habit this week.
  noSlotsForHabit,
}

/// A non-fatal issue surfaced to the user after the scheduler runs.
class SchedulerWarning {
  const SchedulerWarning({required this.message, required this.type});

  final String message;
  final SchedulerWarningType type;

  @override
  String toString() => '[${type.name}] $message';
}

// ── ScheduleResult ────────────────────────────────────────────────────────────

/// The result returned from [AutoScheduler.generateSchedule] and
/// [SchedulerService.runScheduler].
class ScheduleResult {
  const ScheduleResult({required this.events, required this.warnings});

  /// Auto-scheduled event companions ready to be inserted into the database.
  final List<EventsCompanion> events;

  /// Non-fatal warnings generated during scheduling.
  final List<SchedulerWarning> warnings;

  bool get hasWarnings => warnings.isNotEmpty;

  @override
  String toString() =>
      'ScheduleResult(${events.length} events, ${warnings.length} warnings)';
}
