// test/ui/live_providers_test.dart
//
// Event/task providers derived in Dart (recurrence expansion, dashboard
// collapsing) update on their own when the underlying tables change, with no
// manual invalidation, and coalesce bursts of writes.

import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/core/scheduler/scheduler_provider.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      settingsNotifierProvider.overrideWith(
        (ref) => SettingsNotifier.withState(const SettingsState(timezoneMode: 'manual', manualTimezoneOffsetMinutes: 0)),
      ),
    ]);
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// Records every value [provider] emits while the test runs.
  List<T> collect<T>(ProviderListenable<AsyncValue<T>> provider) {
    final values = <T>[];
    container.listen<AsyncValue<T>>(provider, (_, next) {
      if (next.hasValue && !next.isLoading) values.add(next.value as T);
    }, fireImmediately: true);
    return values;
  }

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('todayEventsProvider picks up a new event without invalidation', () async {
    final emitted = collect(todayEventsProvider);
    await until(() => emitted.isNotEmpty);
    expect(emitted.last, isEmpty);

    final todayNoon = DateTime.now().toUtc();
    final start = DateTime.utc(todayNoon.year, todayNoon.month, todayNoon.day, 12);
    await db.eventDao.insertEvent(EventsCompanion.insert(
      title: 'Lecture',
      category: const Value('schoolwork'),
      startTime: start,
      endTime: start.add(const Duration(hours: 1)),
    ));

    await until(() => emitted.last.isNotEmpty);
    expect(emitted.last.map((e) => e.title), ['Lecture']);
  });

  test('dashboardTasksProvider updates when a task is added', () async {
    final emitted = collect(dashboardTasksProvider);
    await until(() => emitted.isNotEmpty);

    await db.taskDao.insertTask(TasksCompanion.insert(
      title: 'Problem Set',
      dueDate: DateTime.now().toUtc().add(const Duration(days: 2)),
    ));

    await until(() => emitted.last.isNotEmpty);
    expect(emitted.last.map((t) => t.title), ['Problem Set']);
  });

  test('a burst of writes coalesces into few reloads', () async {
    final emitted = collect(dashboardTasksProvider);
    await until(() => emitted.isNotEmpty);
    final before = emitted.length;

    for (var i = 0; i < 20; i++) {
      unawaited(db.taskDao.insertTask(TasksCompanion.insert(
        title: 'Task $i',
        dueDate: DateTime.now().toUtc().add(Duration(days: i + 1)),
      )));
    }

    await until(() => emitted.last.length == 20);
    expect(emitted.last, hasLength(20));
    expect(emitted.length - before, lessThan(20));
  });
}
