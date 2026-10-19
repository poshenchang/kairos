// lib/data/database/daos/holiday_dao.dart
//
// Data-access object for Holidays and Academic Breaks.

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/database/tables/holidays_table.dart';

part 'holiday_dao.g.dart';

@DriftAccessor(tables: [Holidays])
class HolidayDao extends DatabaseAccessor<AppDatabase> with _$HolidayDaoMixin {
  HolidayDao(super.db);

  static final Set<String> defaultHolidayNames = {
    "new year's day",
    "martin luther king jr. day",
    "memorial day",
    "juneteenth",
    "independence day",
    "labor day",
    "thanksgiving break",
    "founding day / new year (開國紀念日)",
    "lunar new year break (農曆春節連假)",
    "228 peace memorial day (和平紀念日)",
    "children's day & tomb sweeping (兒童節與清明節)",
    "dragon boat festival (端午節)",
    "mid-autumn festival (中秋節)",
    "national day (國慶日)",
    "spring break",
    "fall break / reading days",
    "winter recess",
  };

  static bool isDefaultHolidayName(String name) =>
      defaultHolidayNames.contains(name.trim().toLowerCase());

  /// Cancels (soft-deletes) all default seeded holidays so they are never active.
  Future<int> cancelAllDefaultHolidays() async {
    final all = await (select(holidays)).get();
    final toCancel = all
        .where((h) => !h.isDeleted && isDefaultHolidayName(h.name))
        .map((h) => h.id)
        .toList();
    if (toCancel.isEmpty) return 0;

    final now = DateTime.now().toUtc();
    return (update(holidays)..where((h) => h.id.isIn(toCancel))).write(
      HolidaysCompanion(
        isDeleted: const Value(true),
        isEnabled: const Value(false),
        updatedAt: Value(now),
      ),
    );
  }

  Future<List<Holiday>> getAllHolidays() async {
    final list = await (select(holidays)
          ..where((h) => h.isDeleted.equals(false))
          ..orderBy([(h) => OrderingTerm.asc(h.date)]))
        .get();
    return _deduplicateInMemory(list);
  }

  Stream<List<Holiday>> watchAllHolidays() =>
      (select(holidays)
            ..where((h) => h.isDeleted.equals(false))
            ..orderBy([(h) => OrderingTerm.asc(h.date)]))
          .watch()
          .map(_deduplicateInMemory);

  List<Holiday> _deduplicateInMemory(List<Holiday> list) {
    final seen = <String>{};
    final result = <Holiday>[];
    for (final h in list) {
      if (h.isDeleted) continue;
      final key = '${h.name.trim().toLowerCase()}|${h.groupName.trim().toLowerCase()}|${h.date.year}-${h.date.month}-${h.date.day}';
      if (seen.add(key)) {
        result.add(h);
      }
    }
    return result;
  }

  Future<int> insertHoliday(HolidaysCompanion holiday) {
    final now = DateTime.now().toUtc();
    final companion = holiday.copyWith(
      syncId: holiday.syncId.present && holiday.syncId.value != null && holiday.syncId.value!.isNotEmpty
          ? holiday.syncId
          : Value(const Uuid().v4()),
      updatedAt: Value(now),
    );
    return into(holidays).insert(companion);
  }

  Future<int> deleteHoliday(int id) async {
    final target = await (select(holidays)..where((h) => h.id.equals(id))).getSingleOrNull();
    final now = DateTime.now().toUtc();
    if (target != null) {
      final targetName = target.name.trim().toLowerCase();
      final all = await (select(holidays)).get();
      final idsToUpdate = all
          .where((h) => h.id == id || h.name.trim().toLowerCase() == targetName)
          .map((h) => h.id)
          .toList();
      return (update(holidays)..where((h) => h.id.isIn(idsToUpdate))).write(
        HolidaysCompanion(
          isDeleted: const Value(true),
          isEnabled: const Value(false),
          updatedAt: Value(now),
        ),
      );
    }
    return (update(holidays)..where((h) => h.id.equals(id))).write(
      HolidaysCompanion(
        isDeleted: const Value(true),
        isEnabled: const Value(false),
        updatedAt: Value(now),
      ),
    );
  }

  Future<int> deleteHolidayGroup(String groupName) => (update(holidays)
        ..where((h) => h.groupName.equals(groupName)))
      .write(HolidaysCompanion(
        isDeleted: const Value(true),
        isEnabled: const Value(false),
        updatedAt: Value(DateTime.now().toUtc()),
      ));

  Future<int> toggleHoliday(int id, bool isEnabled) async {
    final target = await (select(holidays)..where((h) => h.id.equals(id))).getSingleOrNull();
    final now = DateTime.now().toUtc();
    if (target != null) {
      final targetName = target.name.trim().toLowerCase();
      final all = await (select(holidays)).get();
      final idsToUpdate = all
          .where((h) => h.id == id || h.name.trim().toLowerCase() == targetName)
          .map((h) => h.id)
          .toList();
      return (update(holidays)..where((h) => h.id.isIn(idsToUpdate))).write(
        HolidaysCompanion(
          isEnabled: Value(isEnabled),
          updatedAt: Value(now),
        ),
      );
    }
    return (update(holidays)..where((h) => h.id.equals(id))).write(
      HolidaysCompanion(
        isEnabled: Value(isEnabled),
        updatedAt: Value(now),
      ),
    );
  }

  Future<int> toggleHolidayGroup(String groupName, bool isEnabled) =>
      (update(holidays)..where((h) => h.groupName.equals(groupName) & h.isDeleted.equals(false))).write(
        HolidaysCompanion(
          isEnabled: Value(isEnabled),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  Future<bool> updateHoliday(HolidaysCompanion holiday) =>
      update(holidays).replace(
        holiday.copyWith(updatedAt: Value(DateTime.now().toUtc())),
      );

  bool matchesHolidayDate(DateTime date, Holiday h) {
    final targetDate = DateTime(date.year, date.month, date.day);
    if (h.endDate == null || (h.endDate!.month == h.date.month && h.endDate!.day == h.date.day)) {
      return targetDate.month == h.date.month && targetDate.day == h.date.day;
    } else {
      final start = DateTime(date.year, h.date.month, h.date.day);
      final end = DateTime(date.year, h.endDate!.month, h.endDate!.day);
      if (end.isBefore(start)) {
        return (targetDate.month > h.date.month || (targetDate.month == h.date.month && targetDate.day >= h.date.day)) ||
            (targetDate.month < h.endDate!.month || (targetDate.month == h.endDate!.month && targetDate.day <= h.endDate!.day));
      } else {
        return !targetDate.isBefore(start) && !targetDate.isAfter(end);
      }
    }
  }

  Future<List<Holiday>> getHolidaysForDate(DateTime date) async {
    final all = await getAllHolidays();
    return all.where((h) => h.isEnabled && matchesHolidayDate(date, h)).toList();
  }

  Future<bool> isHoliday(DateTime date) async {
    final matching = await getHolidaysForDate(date);
    return matching.isNotEmpty;
  }

  /// Scans all holiday records (including soft-deleted), identifies duplicates by
  /// (name, groupName, date), and marks duplicates with isDeleted = true and updatedAt = now
  /// so Supabase sync propagates the cleanup to cloud storage and all devices.
  Future<int> deduplicateHolidays() async {
    final all = await (select(holidays)..orderBy([(h) => OrderingTerm.desc(h.updatedAt)])).get();
    final groups = <String, List<Holiday>>{};
    for (final h in all) {
      final key = '${h.name.trim().toLowerCase()}|${h.groupName.trim().toLowerCase()}|${h.date.year}-${h.date.month}-${h.date.day}';
      groups.putIfAbsent(key, () => []).add(h);
    }

    final duplicatesToSoftDelete = <int>[];
    for (final list in groups.values) {
      if (list.length <= 1) continue;
      // List is ordered by updatedAt descending.
      // The newest entry represents the authoritative user state.
      final newest = list.first;
      if (newest.isDeleted) {
        // If the newest action was deleting the holiday, ensure ALL copies are soft-deleted.
        for (final h in list) {
          if (!h.isDeleted) duplicatesToSoftDelete.add(h.id);
        }
      } else {
        // If the newest action was keeping it active, keep list.first active and soft-delete the rest.
        for (int i = 1; i < list.length; i++) {
          final dup = list[i];
          if (!dup.isDeleted) duplicatesToSoftDelete.add(dup.id);
        }
      }
    }

    if (duplicatesToSoftDelete.isNotEmpty) {
      final now = DateTime.now().toUtc();
      await (update(holidays)..where((h) => h.id.isIn(duplicatesToSoftDelete))).write(
        HolidaysCompanion(
          isDeleted: const Value(true),
          updatedAt: Value(now),
        ),
      );
    }

    return duplicatesToSoftDelete.length;
  }

  Future<void> seedDefaultHolidays(int year, {bool force = false}) async {
    final allRecords = await (select(holidays)).get();
    if (allRecords.isNotEmpty && !force) {
      return;
    }

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

    final allDefaults = [...usDefaults, ...twDefaults, ...academicDefaults];
    final now = DateTime.now().toUtc();

    for (final def in allDefaults) {
      final defName = def.name.value.trim().toLowerCase();
      final defGroup = def.groupName.value.trim().toLowerCase();

      final existingMatch = allRecords.cast<Holiday?>().firstWhere(
            (r) =>
                r!.name.trim().toLowerCase() == defName &&
                r.groupName.trim().toLowerCase() == defGroup,
            orElse: () => null,
          );

      if (existingMatch == null) {
        await insertHoliday(def);
      } else if (force && existingMatch.isDeleted) {
        await (update(holidays)..where((h) => h.id.equals(existingMatch.id))).write(
          HolidaysCompanion(
            isDeleted: const Value(false),
            isEnabled: const Value(true),
            updatedAt: Value(now),
          ),
        );
      }
    }
  }
}

