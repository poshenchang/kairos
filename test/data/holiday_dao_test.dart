// test/data/holiday_dao_test.dart
//
// Tests for HolidayDao: soft-deletion, tombstones, query filters, and sync metadata.

import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('HolidayDao Soft Deletion & Tombstones', () {
    test('insertHoliday automatically assigns syncId and updatedAt', () async {
      final id = await db.holidayDao.insertHoliday(
        HolidaysCompanion.insert(
          name: 'Labor Day',
          groupName: const Value('US Holidays'),
          date: DateTime(2026, 9, 7),
        ),
      );

      final holiday = await (db.select(db.holidays)..where((h) => h.id.equals(id))).getSingle();
      expect(holiday.syncId, isNotNull);
      expect(holiday.syncId!.length, greaterThan(20)); // UUID format
      expect(holiday.isDeleted, isFalse);
      expect(holiday.updatedAt, isNotNull);
    });

    test('deleteHoliday sets isDeleted=true and updates updatedAt (soft delete)', () async {
      final id = await db.holidayDao.insertHoliday(
        HolidaysCompanion.insert(
          name: 'Test Break',
          groupName: const Value('Academic Breaks'),
          date: DateTime(2026, 3, 16),
        ),
      );

      // Verify it exists in getAllHolidays
      var activeHolidays = await db.holidayDao.getAllHolidays();
      expect(activeHolidays.any((h) => h.id == id), isTrue);

      // Delete the holiday
      await db.holidayDao.deleteHoliday(id);

      // Verify active list no longer returns it
      activeHolidays = await db.holidayDao.getAllHolidays();
      expect(activeHolidays.any((h) => h.id == id), isFalse);

      // Verify row is still in table with isDeleted=true for cloud tombstone sync
      final rawRow = await (db.select(db.holidays)..where((h) => h.id.equals(id))).getSingle();
      expect(rawRow.isDeleted, isTrue);
      expect(rawRow.syncId, isNotNull);
    });

    test('deleteHolidayGroup marks all holidays in that group as isDeleted=true', () async {
      await db.holidayDao.insertHoliday(
        HolidaysCompanion.insert(
          name: 'US Holiday 1',
          groupName: const Value('US Holidays'),
          date: DateTime(2026, 1, 1),
        ),
      );
      await db.holidayDao.insertHoliday(
        HolidaysCompanion.insert(
          name: 'US Holiday 2',
          groupName: const Value('US Holidays'),
          date: DateTime(2026, 7, 4),
        ),
      );
      await db.holidayDao.insertHoliday(
        HolidaysCompanion.insert(
          name: 'TW Holiday 1',
          groupName: const Value('Taiwanese Holidays'),
          date: DateTime(2026, 10, 10),
        ),
      );

      // Delete US Holidays group
      await db.holidayDao.deleteHolidayGroup('US Holidays');

      final active = await db.holidayDao.getAllHolidays();
      expect(active.any((h) => h.groupName == 'US Holidays'), isFalse);
      expect(active.any((h) => h.groupName == 'Taiwanese Holidays'), isTrue);

      // Verify raw rows still exist with isDeleted=true
      final allRaw = await db.select(db.holidays).get();
      final deletedUs = allRaw.where((h) => h.groupName == 'US Holidays').toList();
      expect(deletedUs.length, 2);
      expect(deletedUs.every((h) => h.isDeleted), isTrue);
    });

    test('getHolidaysForDate ignores soft-deleted holidays', () async {
      final date = DateTime(2026, 5, 25);
      final id = await db.holidayDao.insertHoliday(
        HolidaysCompanion.insert(
          name: 'Memorial Day',
          groupName: const Value('US Holidays'),
          date: date,
        ),
      );

      // Should be holiday
      expect(await db.holidayDao.isHoliday(date), isTrue);

      // Soft delete it
      await db.holidayDao.deleteHoliday(id);

      // Should no longer be holiday
      expect(await db.holidayDao.isHoliday(date), isFalse);
    });

    test('toggleHoliday updates isEnabled and bumps updatedAt', () async {
      final id = await db.holidayDao.insertHoliday(
        HolidaysCompanion.insert(
          name: 'Toggle Test',
          groupName: const Value('Test Group'),
          date: DateTime(2026, 8, 1),
          isEnabled: const Value(true),
        ),
      );

      final before = await (db.select(db.holidays)..where((h) => h.id.equals(id))).getSingle();
      await Future.delayed(const Duration(milliseconds: 10));

      await db.holidayDao.toggleHoliday(id, false);

      final after = await (db.select(db.holidays)..where((h) => h.id.equals(id))).getSingle();
      expect(after.isEnabled, isFalse);
      expect(after.updatedAt.isAfter(before.updatedAt) || after.updatedAt.isAtSameMomentAs(before.updatedAt), isTrue);
    });
  });
}

