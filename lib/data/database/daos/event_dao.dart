// lib/data/database/daos/event_dao.dart
//
// Data-access object for Events.

import 'package:drift/drift.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/database/tables/events_table.dart';

part 'event_dao.g.dart';

@DriftAccessor(tables: [Events])
class EventDao extends DatabaseAccessor<AppDatabase> with _$EventDaoMixin {
  EventDao(super.db);

  // ── Queries ──────────────────────────────────────────────────────────────

  /// All non-deleted events, ordered by start time.
  Future<List<Event>> getAllEvents() =>
      (select(events)..where((e) => e.isDeleted.equals(false))
        ..orderBy([(e) => OrderingTerm.asc(e.startTime)]))
          .get();

  /// Non-deleted, non-auto-scheduled events within [start, end].
  Future<List<Event>> getFixedEventsInRange(
      DateTime start, DateTime end) async {
    return (select(events)
          ..where(
            (e) =>
                e.isDeleted.equals(false) &
                e.isAutoScheduled.equals(false) &
                e.startTime.isBiggerOrEqualValue(start) &
                e.endTime.isSmallerOrEqualValue(end),
          )
          ..orderBy([(e) => OrderingTerm.asc(e.startTime)]))
        .get();
  }

  /// All non-deleted events overlapping range [start, end).
  Future<List<Event>> getEventsInRange(DateTime start, DateTime end) =>
      (select(events)
            ..where(
              (e) =>
                  e.isDeleted.equals(false) &
                  e.endTime.isBiggerThanValue(start) &
                  e.startTime.isSmallerThanValue(end),
            )
            ..orderBy([(e) => OrderingTerm.asc(e.startTime)]))
          .get();

  /// Watch non-deleted events overlapping range [start, end).
  Stream<List<Event>> watchEventsInRange(DateTime start, DateTime end) =>
      (select(events)
            ..where(
              (e) =>
                  e.isDeleted.equals(false) &
                  e.endTime.isBiggerThanValue(start) &
                  e.startTime.isSmallerThanValue(end),
            )
            ..orderBy([(e) => OrderingTerm.asc(e.startTime)]))
          .watch();

  /// All auto-scheduled events (used to identify rows to delete on re-run).
  Future<List<Event>> getAutoScheduledEvents() =>
      (select(events)
            ..where((e) =>
                e.isDeleted.equals(false) & e.isAutoScheduled.equals(true)))
          .get();

  /// Single event by id.
  Future<Event?> getEventById(int id) =>
      (select(events)..where((e) => e.id.equals(id))).getSingleOrNull();

  /// Watch today's events (non-deleted, ordered by start).
  Stream<List<Event>> watchEventsForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return (select(events)
          ..where(
            (e) =>
                e.isDeleted.equals(false) &
                e.startTime.isBiggerOrEqualValue(start) &
                e.startTime.isSmallerThanValue(end),
          )
          ..orderBy([(e) => OrderingTerm.asc(e.startTime)]))
        .watch();
  }

  /// Watch all non-deleted events, ordered by start time.
  Stream<List<Event>> watchAllEvents() =>
      (select(events)
            ..where((e) => e.isDeleted.equals(false))
            ..orderBy([(e) => OrderingTerm.asc(e.startTime)]))
          .watch();

  // ── Mutations ─────────────────────────────────────────────────────────────

  /// Insert a single event and return its new id.
  Future<int> insertEvent(EventsCompanion companion) =>
      into(events).insert(companion);

  /// Insert multiple events (e.g. auto-scheduled batch).
  Future<void> insertEvents(List<EventsCompanion> companions) =>
      batch((b) => b.insertAll(events, companions));

  /// Update an existing event.
  Future<bool> updateEvent(EventsCompanion companion) =>
      update(events).replace(companion);

  /// Soft-delete a single event.
  Future<int> deleteEvent(int id) => (update(events)
        ..where((e) => e.id.equals(id)))
      .write(EventsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now().toUtc()),
      ));

  /// Hard-delete all auto-scheduled events.
  /// Called by [SchedulerService] before inserting a fresh schedule.
  Future<int> deleteAutoScheduledEvents() =>
      (delete(events)..where((e) => e.isAutoScheduled.equals(true))).go();

  /// Hard-delete auto-scheduled events within a specific window.
  Future<int> deleteAutoScheduledEventsInRange(
      DateTime start, DateTime end) =>
      (delete(events)
            ..where(
              (e) =>
                  e.isAutoScheduled.equals(true) &
                  e.startTime.isBiggerOrEqualValue(start) &
                  e.endTime.isSmallerOrEqualValue(end),
            ))
          .go();
}
