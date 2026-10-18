// lib/data/repositories/event_repository.dart
//
// Repository that wraps EventDao and adds recurrence-expansion business logic,
// holiday blackout checks, and UNTIL / COUNT termination support.

import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/database/daos/event_dao.dart';
import 'package:kairos/data/database/daos/holiday_dao.dart';

class EventRepository {
  const EventRepository(this._dao, [this._holidayDao]);

  final EventDao _dao;
  final HolidayDao? _holidayDao;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Returns all events in the half-open interval [[start], [end]), with
  /// recurring events expanded into individual occurrences for the range,
  /// skipping active holidays and respecting UNTIL/COUNT limits.
  Future<List<Event>> getExpandedEventsInRange(
    DateTime start,
    DateTime end,
  ) async {
    final allEvents = await _dao.getEventsInRange(
      start.subtract(const Duration(days: 365)),
      end,
    );

    final holidays = await _holidayDao?.getAllHolidays() ?? [];

    final expanded = <Event>[];
    for (final event in allEvents) {
      if (event.isRecurring && event.rrule != null) {
        expanded.addAll(expandRecurringEvents(event, start, end, holidays: holidays));
      } else {
        if (!event.startTime.isBefore(start) && event.startTime.isBefore(end)) {
          expanded.add(event);
        }
      }
    }

    expanded.sort((a, b) => a.startTime.compareTo(b.startTime));
    return expanded;
  }

  /// Expands [baseEvent]'s RRULE into concrete [Event] instances whose
  /// [startTime] falls within [[rangeStart], [rangeEnd]).
  ///
  /// Supports:
  /// - `FREQ=WEEKLY;BYDAY=MO,WE`
  /// - `UNTIL=YYYYMMDDTHHMMSSZ` (terminates recurrence at date)
  /// - `COUNT=N` (terminates recurrence after N occurrences)
  /// - Skipping occurrences on dates matching active [holidays].
  List<Event> expandRecurringEvents(
    Event baseEvent,
    DateTime rangeStart,
    DateTime rangeEnd, {
    List<Holiday> holidays = const [],
  }) {
    final rule = baseEvent.rrule;
    if (rule == null || rule.isEmpty) return [];

    final params = _parseRule(rule);
    if (params['FREQ'] != 'WEEKLY') return [];

    final byDay = params['BYDAY'];
    if (byDay == null || byDay.isEmpty) return [];

    final targetWeekdays = _parseByday(byDay);
    if (targetWeekdays.isEmpty) return [];

    final untilDate = params['UNTIL'] != null ? _parseUntil(params['UNTIL']!) : null;
    final maxCount = params['COUNT'] != null ? int.tryParse(params['COUNT']!) : null;

    final duration = baseEvent.endTime.difference(baseEvent.startTime);
    final baseStart = baseEvent.startTime;

    final occurrences = <Event>[];

    // If maxCount is specified, walk from baseEvent's original start to track occurrence count
    var current = maxCount != null
        ? DateTime(baseStart.year, baseStart.month, baseStart.day)
        : DateTime(rangeStart.year, rangeStart.month, rangeStart.day);

    final exclusiveEnd = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day)
        .add(const Duration(days: 1));

    int totalOccurrencesSeen = 0;

    while (current.isBefore(exclusiveEnd)) {
      if (targetWeekdays.contains(current.weekday)) {
        final occurrenceStart = DateTime(
          current.year,
          current.month,
          current.day,
          baseStart.hour,
          baseStart.minute,
          baseStart.second,
        );

        // Check if past UNTIL date
        if (untilDate != null && occurrenceStart.isAfter(untilDate)) {
          break;
        }

        totalOccurrencesSeen++;
        if (maxCount != null && totalOccurrencesSeen > maxCount) {
          break;
        }

        // Check if date is a holiday (classes and weekly routines are disabled on holidays)
        final isHolidayDate = _isHoliday(current, holidays);

        if (!isHolidayDate) {
          if (!occurrenceStart.isBefore(rangeStart) && occurrenceStart.isBefore(rangeEnd)) {
            occurrences.add(
              baseEvent.copyWith(
                startTime: occurrenceStart,
                endTime: occurrenceStart.add(duration),
              ),
            );
          }
        }
      }
      current = current.add(const Duration(days: 1));
    }

    return occurrences;
  }

  bool _isHoliday(DateTime date, List<Holiday> holidays) {
    if (holidays.isEmpty) return false;
    final target = DateTime(date.year, date.month, date.day);
    for (final h in holidays) {
      if (!h.isEnabled) continue;
      final start = DateTime(h.date.year, h.date.month, h.date.day);
      final end = h.endDate != null
          ? DateTime(h.endDate!.year, h.endDate!.month, h.endDate!.day)
          : start;
      if (!target.isBefore(start) && !target.isAfter(end)) {
        return true;
      }
    }
    return false;
  }

  DateTime? _parseUntil(String untilStr) {
    try {
      final clean = untilStr.replaceAll('-', '').replaceAll(':', '');
      if (clean.length >= 8) {
        final y = int.parse(clean.substring(0, 4));
        final m = int.parse(clean.substring(4, 6));
        final d = int.parse(clean.substring(6, 8));
        return DateTime(y, m, d, 23, 59, 59);
      }
    } catch (_) {}
    return null;
  }

  // ── EventDao delegation ───────────────────────────────────────────────────

  Stream<List<Event>> watchEventsInRange(DateTime start, DateTime end) =>
      _dao.watchEventsInRange(start, end);

  Stream<List<Event>> watchEventsForDay(DateTime day) =>
      _dao.watchEventsForDay(day);

  Future<List<Event>> getEventsInRange(DateTime start, DateTime end) =>
      _dao.getEventsInRange(start, end);

  Future<List<Event>> getAutoScheduledEvents() =>
      _dao.getAutoScheduledEvents();

  Future<Event?> getEventById(int id) => _dao.getEventById(id);

  Future<int> insertEvent(EventsCompanion event) =>
      _dao.insertEvent(event);

  Future<bool> updateEvent(EventsCompanion event) =>
      _dao.updateEvent(event);

  Future<int> deleteEvent(int id) => _dao.deleteEvent(id);

  Future<int> deleteAutoScheduledEvents() =>
      _dao.deleteAutoScheduledEvents();

  // ── Private helpers ───────────────────────────────────────────────────────

  Map<String, String> _parseRule(String rule) => {
        for (final part in rule.split(';'))
          if (part.contains('='))
            part.split('=').first.trim().toUpperCase():
                part.split('=').last.trim().toUpperCase(),
      };

  Set<int> _parseByday(String byday) {
    const dayMap = {
      'MO': DateTime.monday,
      'TU': DateTime.tuesday,
      'WE': DateTime.wednesday,
      'TH': DateTime.thursday,
      'FR': DateTime.friday,
      'SA': DateTime.saturday,
      'SU': DateTime.sunday,
    };
    return {
      for (final token in byday.split(','))
        if (dayMap.containsKey(token.trim())) dayMap[token.trim()]!,
    };
  }
}
