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

    test('seedDefaultHolidays does not duplicate holidays on repeated calls', () async {
      await db.holidayDao.seedDefaultHolidays(2026);
      final initialCount = (await db.holidayDao.getAllHolidays()).length;
      expect(initialCount, greaterThan(0));

      // Call again - should be no-op
      await db.holidayDao.seedDefaultHolidays(2026);
      final secondCount = (await db.holidayDao.getAllHolidays()).length;
      expect(secondCount, equals(initialCount));
    });

    test('seedDefaultHolidays does not resurrect deleted group unless forced', () async {
      await db.holidayDao.seedDefaultHolidays(2026);
      await db.holidayDao.deleteHolidayGroup('Taiwanese Holidays');

      var active = await db.holidayDao.getAllHolidays();
      expect(active.any((h) => h.groupName == 'Taiwanese Holidays'), isFalse);

      // Normal seed should NOT resurrect or duplicate
      await db.holidayDao.seedDefaultHolidays(2026, force: false);
      active = await db.holidayDao.getAllHolidays();
      expect(active.any((h) => h.groupName == 'Taiwanese Holidays'), isFalse);

      // Forced seed will resurrect
      await db.holidayDao.seedDefaultHolidays(2026, force: true);
      active = await db.holidayDao.getAllHolidays();
      expect(active.any((h) => h.groupName == 'Taiwanese Holidays'), isTrue);
    });

    test('deduplicateHolidays marks duplicate rows as isDeleted=true', () async {
      // Manually insert 3 duplicates of the same holiday with different syncIds
      await db.holidayDao.insertHoliday(
        HolidaysCompanion.insert(
          name: 'Duplicate Day',
          groupName: const Value('Custom'),
          date: DateTime(2026, 12, 1),
        ),
      );
      await db.holidayDao.insertHoliday(
        HolidaysCompanion.insert(
          name: 'Duplicate Day',
          groupName: const Value('Custom'),
          date: DateTime(2026, 12, 1),
        ),
      );
      await db.holidayDao.insertHoliday(
        HolidaysCompanion.insert(
          name: 'Duplicate Day',
          groupName: const Value('Custom'),
          date: DateTime(2026, 12, 1),
        ),
      );

      final beforeRaw = (await db.select(db.holidays).get()).where((h) => h.name == 'Duplicate Day').toList();
      expect(beforeRaw.length, 3);

      // In-memory filter prevents UI from seeing all 3
      final activeBeforeDedup = (await db.holidayDao.getAllHolidays()).where((h) => h.name == 'Duplicate Day').toList();
      expect(activeBeforeDedup.length, 1);

      // Run DB deduplication
      final purged = await db.holidayDao.deduplicateHolidays();
      expect(purged, 2);

      final afterRaw = (await db.select(db.holidays).get()).where((h) => h.name == 'Duplicate Day').toList();
      final activeCount = afterRaw.where((h) => !h.isDeleted).length;
      final deletedCount = afterRaw.where((h) => h.isDeleted).length;
      expect(activeCount, 1);
      expect(deletedCount, 2);
    });

    test('cancelAllDefaultHolidays marks all default holidays as isDeleted=true and preserves custom holidays', () async {
      await db.holidayDao.seedDefaultHolidays(2026, force: true);
      await db.holidayDao.insertHoliday(
        HolidaysCompanion.insert(
          name: 'My Custom Break',
          groupName: const Value('Custom'),
          date: DateTime(2026, 7, 10),
        ),
      );

      final before = await db.holidayDao.getAllHolidays();
      expect(before.any((h) => h.name == 'New Year\'s Day'), isTrue);
      expect(before.any((h) => h.name == 'My Custom Break'), isTrue);

      final cancelled = await db.holidayDao.cancelAllDefaultHolidays();
      expect(cancelled, greaterThan(10));

      final after = await db.holidayDao.getAllHolidays();
      expect(after.any((h) => h.name == 'New Year\'s Day'), isFalse);
      expect(after.any((h) => h.name == 'Memorial Day'), isFalse);
      expect(after.any((h) => h.name == 'My Custom Break'), isTrue);
    });

    test('deleteHoliday marks all copies of the same holiday name as isDeleted=true', () async {
      await db.holidayDao.insertHoliday(
        HolidaysCompanion.insert(
          name: 'Conference Day',
          groupName: const Value('Academic Breaks'),
          date: DateTime(2026, 11, 5),
        ),
      );
      final id2 = await db.holidayDao.insertHoliday(
        HolidaysCompanion.insert(
          name: 'Conference Day',
          groupName: const Value('Academic Breaks'),
          date: DateTime(2026, 11, 5, 8, 0),
        ),
      );

      await db.holidayDao.deleteHoliday(id2);

      final all = await db.select(db.holidays).get();
      final matching = all.where((h) => h.name == 'Conference Day');
      for (final h in matching) {
        expect(h.isDeleted, isTrue);
        expect(h.isEnabled, isFalse);
      }
    });

    test('toggleHoliday toggles all copies of the same holiday name', () async {
      await db.holidayDao.insertHoliday(
        HolidaysCompanion.insert(
          name: 'Symposium',
          groupName: const Value('Academic Breaks'),
          date: DateTime(2026, 11, 10),
        ),
      );
      final id2 = await db.holidayDao.insertHoliday(
        HolidaysCompanion.insert(
          name: 'Symposium',
          groupName: const Value('Academic Breaks'),
          date: DateTime(2026, 11, 10, 8, 0),
        ),
      );

      await db.holidayDao.toggleHoliday(id2, false);

      final all = await db.select(db.holidays).get();
      final matching = all.where((h) => h.name == 'Symposium');
      for (final h in matching) {
        expect(h.isEnabled, isFalse);
      }
    });
  });
}

