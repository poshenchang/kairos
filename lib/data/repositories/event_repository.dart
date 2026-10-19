// lib/data/repositories/event_repository.dart
//
// Repository that wraps EventDao and adds recurrence-expansion business logic,
// holiday blackout checks, and UNTIL / COUNT termination support.

import 'package:drift/drift.dart' show Value;
import 'package:kairos/data/database/app_database.dart';

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
    final holidayDaySet = _buildHolidayDaySet(holidays);

    final expanded = <Event>[];
    for (final event in allEvents) {
      if (event.isRecurring && event.rrule != null) {
        expanded.addAll(expandRecurringEvents(
          event,
          start,
          end,
          holidays: holidays,
          holidayDaySet: holidayDaySet,
        ));
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
  /// - `FREQ=DAILY` (daily recurring habit/routine events)
  /// - `UNTIL=YYYYMMDDTHHMMSSZ` (terminates recurrence at date)
  /// - `COUNT=N` (terminates recurrence after N occurrences)
  /// - Skipping occurrences on dates matching active [holidays] for academic/work events.
  List<Event> expandRecurringEvents(
    Event baseEvent,
    DateTime rangeStart,
    DateTime rangeEnd, {
    List<Holiday> holidays = const [],
    Set<int>? holidayDaySet,
  }) {
    final rule = baseEvent.rrule;
    if (rule == null || rule.isEmpty) return [];

    final activeHolidaySet = holidayDaySet ?? (holidays.isNotEmpty ? _buildHolidayDaySet(holidays) : null);

    final params = _parseRule(rule);
    final freq = params['FREQ'];
    if (freq != 'WEEKLY' && freq != 'DAILY') return [];

    final targetWeekdays = freq == 'WEEKLY'
        ? (params['BYDAY'] != null ? _parseByday(params['BYDAY']!) : <int>[])
        : null;

    if (freq == 'WEEKLY' && (targetWeekdays == null || targetWeekdays.isEmpty)) {
      return [];
    }

    final untilDate = params['UNTIL'] != null ? _parseUntil(params['UNTIL']!) : null;
    final maxCount = params['COUNT'] != null ? int.tryParse(params['COUNT']!) : null;

    // Parse temporarily cancelled occurrence dates (EXDATE=YYYY-MM-DD,...)
    final cancelledDates = <String>{};
    if (params['EXDATE'] != null) {
      for (final part in params['EXDATE']!.split(',')) {
        final trimmed = part.trim();
        if (trimmed.isNotEmpty) cancelledDates.add(trimmed);
      }
    }

    final duration = baseEvent.endTime.difference(baseEvent.startTime);
    final baseStart = baseEvent.startTime;

    final occurrences = <Event>[];

    final baseDay = DateTime(baseStart.year, baseStart.month, baseStart.day);
    final rangeDay = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);

    // Walk dates starting from baseEvent's start day or rangeStart, whichever is later
    // unless maxCount is set (then we must walk from baseStart to accurately count occurrences)
    var current = (maxCount != null || rangeDay.isBefore(baseDay)) ? baseDay : rangeDay;

    final exclusiveEnd = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day)
        .add(const Duration(days: 1));

    int totalOccurrencesSeen = 0;
    final isDaily = freq == 'DAILY';

    while (current.isBefore(exclusiveEnd)) {
      final matchesDay = isDaily || (targetWeekdays != null && targetWeekdays.contains(current.weekday));
      if (matchesDay) {
        final occurrenceStart = DateTime(
          current.year,
          current.month,
          current.day,
          baseStart.hour,
          baseStart.minute,
          baseStart.second,
        );

        // Never produce occurrences before the recurring series actually begins!
        if (occurrenceStart.isBefore(baseStart)) {
          current = current.add(const Duration(days: 1));
          continue;
        }

        // Check if past UNTIL date
        if (untilDate != null && occurrenceStart.isAfter(untilDate)) {
          break;
        }

        totalOccurrencesSeen++;
        if (maxCount != null && totalOccurrencesSeen > maxCount) {
          break;
        }

        // Format dateKey: YYYY-MM-DD
        final dateKey = '${current.year}-${current.month.toString().padLeft(2, '0')}-${current.day.toString().padLeft(2, '0')}';

        // Check if this specific occurrence is temporarily cancelled
        final isCancelled = cancelledDates.contains(dateKey);

        // Academic breaks & holidays: disable lectures, classes, and work routines,
        // while allowing personal daily habits (language learning, podcasts) to continue!
        final isAcademicEvent = baseEvent.eventType == 'lecture' ||
            baseEvent.category == 'schoolwork' ||
            baseEvent.category == 'work';
        final isHolidayDate = isAcademicEvent &&
            (activeHolidaySet != null
                ? activeHolidaySet.contains(current.month * 100 + current.day)
                : _isHoliday(current, holidays));

        if (!isHolidayDate && !isCancelled) {
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

  /// Builds a hash set of (month * 100 + day) for all active holidays.
  /// Allows O(1) checking instead of an O(H) loop over every day.
  Set<int> _buildHolidayDaySet(List<Holiday> holidays) {
    final set = <int>{};
    for (final h in holidays) {
      if (!h.isEnabled) continue;
      if (h.endDate == null || (h.endDate!.month == h.date.month && h.endDate!.day == h.date.day)) {
        set.add(h.date.month * 100 + h.date.day);
      } else {
        var cur = DateTime(2024, h.date.month, h.date.day); // Leap year to safely support Feb 29
        var end = DateTime(2024, h.endDate!.month, h.endDate!.day);
        if (end.isBefore(cur)) {
          end = DateTime(2025, h.endDate!.month, h.endDate!.day);
        }
        while (!cur.isAfter(end)) {
          set.add(cur.month * 100 + cur.day);
          cur = cur.add(const Duration(days: 1));
        }
      }
    }
    return set;
  }

  /// Finds any active events that overlap with [[start], [end]).
  /// Ignores soft-deleted events, the event with [excludeEventId] (when editing),
  /// and reminder events (since reminders have zero duration).
  Future<List<Event>> getConflictingEvents(
    DateTime start,
    DateTime end, {
    int? excludeEventId,
  }) async {
    final dayStart = DateTime(start.year, start.month, start.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final events = await getExpandedEventsInRange(dayStart, dayEnd);
    return events.where((e) {
      if (excludeEventId != null && e.id == excludeEventId) return false;
      if (e.isDeleted) return false;
      if (e.eventType == 'reminder') return false;
      return start.isBefore(e.endTime) && end.isAfter(e.startTime);
    }).toList();
  }

  /// Checks if [date] falls on any active holiday.
  /// Holidays repeat annually matching month and day (ignoring specific calendar year).
  bool _isHoliday(DateTime date, List<Holiday> holidays) {
    if (holidays.isEmpty) return false;
    final target = DateTime(date.year, date.month, date.day);
    for (final h in holidays) {
      if (!h.isEnabled) continue;

      if (h.endDate == null || (h.endDate!.month == h.date.month && h.endDate!.day == h.date.day)) {
        if (target.month == h.date.month && target.day == h.date.day) {
          return true;
        }
      } else {
        final start = DateTime(date.year, h.date.month, h.date.day);
        final end = DateTime(date.year, h.endDate!.month, h.endDate!.day);
        if (end.isBefore(start)) {
          // Span wraps around year-end (e.g. Dec 25 - Jan 5)
          if ((target.month > h.date.month || (target.month == h.date.month && target.day >= h.date.day)) ||
              (target.month < h.endDate!.month || (target.month == h.endDate!.month && target.day <= h.endDate!.day))) {
            return true;
          }
        } else {
          if (!target.isBefore(start) && !target.isAfter(end)) {
            return true;
          }
        }
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

  // ── Occurrence Cancellation & Restoration ──────────────────────────────────

  /// Temporarily cancels a specific occurrence of a recurring event on [date].
  /// Appends `EXDATE=YYYY-MM-DD` to the event's RRULE in the database.
  Future<void> cancelRecurringOccurrence(int eventId, DateTime date) async {
    final event = await _dao.getEventById(eventId);
    if (event == null || !event.isRecurring) return;

    final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final currentRule = event.rrule ?? 'FREQ=WEEKLY';
    final newRule = addExdateToRrule(currentRule, dateKey);

    await _dao.updateEvent(event.toCompanion(true).copyWith(
      rrule: Value(newRule),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  /// Restores a previously cancelled occurrence of a recurring event on [dateKey] (YYYY-MM-DD).
  Future<void> restoreRecurringOccurrence(int eventId, String dateKey) async {
    final event = await _dao.getEventById(eventId);
    if (event == null || !event.isRecurring || event.rrule == null) return;

    final newRule = removeExdateFromRrule(event.rrule!, dateKey);
    await _dao.updateEvent(event.toCompanion(true).copyWith(
      rrule: Value(newRule),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  /// Extracts all cancelled date strings (YYYY-MM-DD) from an RRULE.
  static List<String> getCancelledDates(String? rrule) {
    if (rrule == null || rrule.isEmpty) return [];
    final match = RegExp(r'EXDATE=([^;]+)').firstMatch(rrule);
    if (match == null) return [];
    return match.group(1)!.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  /// Adds a dateKey (YYYY-MM-DD) to an RRULE's EXDATE clause.
  static String addExdateToRrule(String rrule, String dateKey) {
    final parts = rrule.split(';').toList();
    int exdateIndex = parts.indexWhere((p) => p.startsWith('EXDATE='));

    if (exdateIndex != -1) {
      final existing = parts[exdateIndex].substring(7).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (!existing.contains(dateKey)) {
        existing.add(dateKey);
      }
      parts[exdateIndex] = 'EXDATE=${existing.join(',')}';
    } else {
      parts.add('EXDATE=$dateKey');
    }

    return parts.join(';');
  }

  /// Removes a dateKey (YYYY-MM-DD) from an RRULE's EXDATE clause.
  static String removeExdateFromRrule(String rrule, String dateKey) {
    final parts = rrule.split(';').toList();
    int exdateIndex = parts.indexWhere((p) => p.startsWith('EXDATE='));

    if (exdateIndex != -1) {
      final existing = parts[exdateIndex].substring(7).split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      existing.remove(dateKey);
      if (existing.isEmpty) {
        parts.removeAt(exdateIndex);
      } else {
        parts[exdateIndex] = 'EXDATE=${existing.join(',')}';
      }
    }

    return parts.join(';');
  }

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
