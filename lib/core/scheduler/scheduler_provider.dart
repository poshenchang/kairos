// lib/core/scheduler/scheduler_provider.dart
//
// Riverpod providers for the scheduler layer.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/core/scheduler/scheduler_service.dart';
import 'package:kairos/core/scheduler/scheduler_types.dart';

// ── Database provider (singleton) ─────────────────────────────────────────────

/// Provides the singleton [AppDatabase] instance.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

// ── SchedulerService provider ─────────────────────────────────────────────────

/// Provides the [SchedulerService] configured with the live database.
final schedulerServiceProvider = Provider<SchedulerService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SchedulerService(db: db);
});

// ── Scheduler state ───────────────────────────────────────────────────────────

/// Notifier that runs the scheduler and exposes the latest [ScheduleResult].
///
/// Usage:
/// ```dart
/// // Trigger a full re-schedule:
/// ref.read(schedulerNotifierProvider.notifier).run();
///
/// // Watch for warnings / results:
/// final state = ref.watch(schedulerNotifierProvider);
/// ```
class SchedulerNotifier extends AsyncNotifier<ScheduleResult?> {
  @override
  Future<ScheduleResult?> build() async => null;

  /// Run the scheduler for the default 7-day window.
  Future<void> run() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(schedulerServiceProvider).runScheduler(),
    );
  }

  /// Run the scheduler for a custom window.
  Future<void> runForWindow(DateTime start, DateTime end) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(schedulerServiceProvider).runSchedulerForWindow(start, end),
    );
  }
}

final schedulerNotifierProvider =
    AsyncNotifierProvider<SchedulerNotifier, ScheduleResult?>(
  SchedulerNotifier.new,
);
