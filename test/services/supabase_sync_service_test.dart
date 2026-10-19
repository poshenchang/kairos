// test/services/supabase_sync_service_test.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/supabase_sync_service.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('SupabaseSyncService Concurrency & Validation Tests', () {
    test('isConfigured is false when URL or key is empty', () {
      const settings = SettingsState(
        supabaseUrl: '',
        supabasePublishableKey: '',
      );
      final syncService = SupabaseSyncService(db, settings);

      expect(syncService.isConfigured, isFalse);
    });

    test('syncNow returns false and sets error status when not configured', () async {
      const settings = SettingsState(
        supabaseUrl: '',
        supabasePublishableKey: '',
      );
      final syncService = SupabaseSyncService(db, settings);

      final result = await syncService.syncNow();
      expect(result, isFalse);
      expect(syncService.state.status, equals(SyncStatus.error));
      expect(syncService.state.errorMessage, contains('not configured'));
    });

    test('isConfigured is true when both URL and key are provided', () {
      const settings = SettingsState(
        supabaseUrl: 'https://xyzcompany.supabase.co',
        supabasePublishableKey: 'sb_publishable_dummy_key_123',
      );
      final syncService = SupabaseSyncService(db, settings);

      expect(syncService.isConfigured, isTrue);
    });

    test('Local records get auto-assigned unique syncId UUIDs', () async {
      // Insert test category and event without syncId
      final catId = await db.into(db.categories).insert(
            CategoriesCompanion.insert(
              name: 'Test Cat',
              slug: 'test-cat',
            ),
          );

      final eventId = await db.into(db.events).insert(
            EventsCompanion.insert(
              title: 'Test Event',
              startTime: DateTime.now(),
              endTime: DateTime.now().add(const Duration(hours: 1)),
            ),
          );

      var cat = await (db.select(db.categories)..where((t) => t.id.equals(catId))).getSingle();
      var event = await (db.select(db.events)..where((t) => t.id.equals(eventId))).getSingle();

      expect(cat.syncId, isNull);
      expect(event.syncId, isNull);

      // Initialize service with invalid URL to test pre-sync ID generation before network call
      const settings = SettingsState(
        supabaseUrl: 'https://invalid-non-existent-supabase-project.supabase.co',
        supabasePublishableKey: 'sb_publishable_dummy',
      );
      final syncService = SupabaseSyncService(db, settings);

      // Attempt sync (network will fail, but syncIds must be assigned beforehand)
      await syncService.syncNow();

      cat = await (db.select(db.categories)..where((t) => t.id.equals(catId))).getSingle();
      event = await (db.select(db.events)..where((t) => t.id.equals(eventId))).getSingle();

      expect(cat.syncId, isNotNull);
      expect(cat.syncId!.length, greaterThan(20)); // UUID format
      expect(event.syncId, isNotNull);
      expect(event.syncId!.length, greaterThan(20));
    });
  });
}

