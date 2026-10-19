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

  Future<int> toggleHolidayGroup(String groupName, bool isEnabled) =>
      (update(holidays)..where((h) => h.groupName.equals(groupName))).write(
        HolidaysCompanion(isEnabled: Value(isEnabled)),
      );

  Future<bool> updateHoliday(HolidaysCompanion holiday) =>
      update(holidays).replace(holiday);

  Future<bool> isHoliday(DateTime date) async {
    final activeHolidays = await (select(holidays)
          ..where((h) => h.isEnabled.equals(true)))
        .get();

    final targetDate = DateTime(date.year, date.month, date.day);

    for (final h in activeHolidays) {
      if (h.endDate == null || (h.endDate!.month == h.date.month && h.endDate!.day == h.date.day)) {
        if (targetDate.month == h.date.month && targetDate.day == h.date.day) {
          return true;
        }
      } else {
        final start = DateTime(date.year, h.date.month, h.date.day);
        final end = DateTime(date.year, h.endDate!.month, h.endDate!.day);
        if (end.isBefore(start)) {
          if ((targetDate.month > h.date.month || (targetDate.month == h.date.month && targetDate.day >= h.date.day)) ||
              (targetDate.month < h.endDate!.month || (targetDate.month == h.endDate!.month && targetDate.day <= h.endDate!.day))) {
            return true;
          }
        } else {
          if (!targetDate.isBefore(start) && !targetDate.isAfter(end)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  Future<void> seedDefaultHolidays(int year) async {
    final existing = await getAllHolidays();

    final usDefaults = [
      HolidaysCompanion.insert(
        name: 'New Year\'s Day',
        groupName: const Value('US Holidays'),
        date: DateTime(year, 1, 1),
      ),
      HolidaysCompanion.insert(
        name: 'Martin Luther King Jr. Day',
        groupName: const Value('US Holidays'),
        date: DateTime(year, 1, 19),
      ),
      HolidaysCompanion.insert(
        name: 'Memorial Day',
        groupName: const Value('US Holidays'),
        date: DateTime(year, 5, 25),
      ),
      HolidaysCompanion.insert(
        name: 'Juneteenth',
        groupName: const Value('US Holidays'),
        date: DateTime(year, 6, 19),
      ),
      HolidaysCompanion.insert(
        name: 'Independence Day',
        groupName: const Value('US Holidays'),
        date: DateTime(year, 7, 4),
      ),
      HolidaysCompanion.insert(
        name: 'Labor Day',
        groupName: const Value('US Holidays'),
        date: DateTime(year, 9, 7),
      ),
      HolidaysCompanion.insert(
        name: 'Thanksgiving Break',
        groupName: const Value('US Holidays'),
        date: DateTime(year, 11, 26),
        endDate: Value(DateTime(year, 11, 27)),
      ),
    ];

    final twDefaults = [
      HolidaysCompanion.insert(
        name: 'Founding Day / New Year (開國紀念日)',
        groupName: const Value('Taiwanese Holidays'),
        date: DateTime(year, 1, 1),
      ),
      HolidaysCompanion.insert(
        name: 'Lunar New Year Break (農曆春節連假)',
        groupName: const Value('Taiwanese Holidays'),
        date: DateTime(year, 2, 14),
        endDate: Value(DateTime(year, 2, 20)),
      ),
      HolidaysCompanion.insert(
        name: '228 Peace Memorial Day (和平紀念日)',
        groupName: const Value('Taiwanese Holidays'),
        date: DateTime(year, 2, 28),
      ),
      HolidaysCompanion.insert(
        name: 'Children\'s Day & Tomb Sweeping (兒童節與清明節)',
        groupName: const Value('Taiwanese Holidays'),
        date: DateTime(year, 4, 3),
        endDate: Value(DateTime(year, 4, 6)),
      ),
      HolidaysCompanion.insert(
        name: 'Dragon Boat Festival (端午節)',
        groupName: const Value('Taiwanese Holidays'),
        date: DateTime(year, 6, 19),
      ),
      HolidaysCompanion.insert(
        name: 'Mid-Autumn Festival (中秋節)',
        groupName: const Value('Taiwanese Holidays'),
        date: DateTime(year, 9, 25),
      ),
      HolidaysCompanion.insert(
        name: 'National Day (國慶日)',
        groupName: const Value('Taiwanese Holidays'),
        date: DateTime(year, 10, 10),
      ),
    ];

    final academicDefaults = [
      HolidaysCompanion.insert(
        name: 'Spring Break',
        groupName: const Value('Academic Breaks'),
        date: DateTime(year, 3, 16),
        endDate: Value(DateTime(year, 3, 20)),
      ),
      HolidaysCompanion.insert(
        name: 'Fall Break / Reading Days',
        groupName: const Value('Academic Breaks'),
        date: DateTime(year, 10, 12),
        endDate: Value(DateTime(year, 10, 13)),
      ),
      HolidaysCompanion.insert(
        name: 'Winter Recess',
        groupName: const Value('Academic Breaks'),
        date: DateTime(year, 12, 23),
        endDate: Value(DateTime(year, 12, 31)),
      ),
    ];

    if (existing.isEmpty) {
      for (final h in [...usDefaults, ...twDefaults, ...academicDefaults]) {
        await insertHoliday(h);
      }
    } else {
      // Ensure Taiwanese holidays exist
      final hasTw = existing.any((h) => h.groupName == 'Taiwanese Holidays');
      if (!hasTw) {
        for (final h in twDefaults) {
          await insertHoliday(h);
        }
      }
      // Ensure Academic breaks exist
      final hasAcademic = existing.any((h) => h.groupName == 'Academic Breaks');
      if (!hasAcademic) {
        for (final h in academicDefaults) {
          await insertHoliday(h);
        }
      }
    }
  }
}

