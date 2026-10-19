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

    test('URL sanitization strips trailing slashes, /rest/v1, and handles dashboard URLs', () {
      final s1 = SupabaseSyncService(db, const SettingsState(
        supabaseUrl: 'https://xyzcompany.supabase.co/rest/v1/',
        supabasePublishableKey: 'key',
      ));
      expect(s1.cleanBaseUrl, 'https://xyzcompany.supabase.co');

      final s2 = SupabaseSyncService(db, const SettingsState(
        supabaseUrl: 'https://xyzcompany.supabase.co/rest',
        supabasePublishableKey: 'key',
      ));
      expect(s2.cleanBaseUrl, 'https://xyzcompany.supabase.co');

      final s3 = SupabaseSyncService(db, const SettingsState(
        supabaseUrl: 'https://supabase.com/dashboard/project/abcdefghij',
        supabasePublishableKey: 'key',
      ));
      expect(s3.cleanBaseUrl, 'https://abcdefghij.supabase.co');
    });

    test('PGRST125 returns clear instructions to run SQL setup script', () {
      final syncService = SupabaseSyncService(db, const SettingsState());
      final msg = syncService.humanReadableError(
        'Categories sync failed (404): {"code":"PGRST125","details":null,"hint":null,"message":"Invalid path specified in request URL"}',
      );
      expect(msg, contains('SQL Setup'));
    });

    test('42501 permission denied returns clear instructions to grant privileges', () {
      final syncService = SupabaseSyncService(db, const SettingsState());
      final msg = syncService.humanReadableError(
        'Categories sync failed (401): {"code":"42501","details":null,"hint":"Grant the required privileges to the current role with: GRANT SELECT ON public.categories TO anon;","message":"permission denied for table categories"}',
      );
      expect(msg, contains('Database permission denied (42501)'));
      expect(msg, contains('SQL Setup'));
    });
  });
}

