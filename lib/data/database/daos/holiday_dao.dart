// lib/data/database/daos/holiday_dao.dart
//
// Data-access object for Holidays and Academic Breaks.

import 'package:drift/drift.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/database/tables/holidays_table.dart';

part 'holiday_dao.g.dart';

@DriftAccessor(tables: [Holidays])
class HolidayDao extends DatabaseAccessor<AppDatabase> with _$HolidayDaoMixin {
  HolidayDao(super.db);

  Future<List<Holiday>> getAllHolidays() =>
      (select(holidays)..orderBy([(h) => OrderingTerm.asc(h.date)])).get();

  Stream<List<Holiday>> watchAllHolidays() =>
      (select(holidays)..orderBy([(h) => OrderingTerm.asc(h.date)])).watch();

  Future<int> insertHoliday(HolidaysCompanion holiday) =>
      into(holidays).insert(holiday);

  Future<int> deleteHoliday(int id) =>
      (delete(holidays)..where((h) => h.id.equals(id))).go();

  Future<int> toggleHoliday(int id, bool isEnabled) =>
      (update(holidays)..where((h) => h.id.equals(id))).write(
        HolidaysCompanion(isEnabled: Value(isEnabled)),
      );

  Future<bool> isHoliday(DateTime date) async {
    final activeHolidays = await (select(holidays)
          ..where((h) => h.isEnabled.equals(true)))
        .get();

    final targetDate = DateTime(date.year, date.month, date.day);

    for (final h in activeHolidays) {
      final start = DateTime(h.date.year, h.date.month, h.date.day);
      final end = h.endDate != null
          ? DateTime(h.endDate!.year, h.endDate!.month, h.endDate!.day)
          : start;

      if (!targetDate.isBefore(start) && !targetDate.isAfter(end)) {
        return true;
      }
    }
    return false;
  }

  Future<void> seedDefaultHolidays(int year) async {
    final existing = await getAllHolidays();
    if (existing.isNotEmpty) return;

    final defaults = [
      HolidaysCompanion.insert(
        name: 'New Year\'s Day',
        date: DateTime(year, 1, 1),
      ),
      HolidaysCompanion.insert(
        name: 'Martin Luther King Jr. Day',
        date: DateTime(year, 1, 19),
      ),
      HolidaysCompanion.insert(
        name: 'Spring Break',
        date: DateTime(year, 3, 16),
        endDate: Value(DateTime(year, 3, 20)),
      ),
      HolidaysCompanion.insert(
        name: 'Memorial Day',
        date: DateTime(year, 5, 25),
      ),
      HolidaysCompanion.insert(
        name: 'Juneteenth',
        date: DateTime(year, 6, 19),
      ),
      HolidaysCompanion.insert(
        name: 'Independence Day',
        date: DateTime(year, 7, 4),
      ),
      HolidaysCompanion.insert(
        name: 'Labor Day',
        date: DateTime(year, 9, 7),
      ),
      HolidaysCompanion.insert(
        name: 'Fall Break / Reading Days',
        date: DateTime(year, 10, 12),
        endDate: Value(DateTime(year, 10, 13)),
      ),
      HolidaysCompanion.insert(
        name: 'Thanksgiving Break',
        date: DateTime(year, 11, 26),
        endDate: Value(DateTime(year, 11, 27)),
      ),
      HolidaysCompanion.insert(
        name: 'Winter Recess',
        date: DateTime(year, 12, 23),
        endDate: Value(DateTime(year, 12, 31)),
      ),
    ];

    for (final h in defaults) {
      await insertHoliday(h);
    }
  }
}

