// lib/services/supabase_sync_service.dart
//
// Robust, offline-first cloud synchronization service for Supabase.
// Handles multi-device concurrency, Last-Write-Wins (LWW) conflict resolution,
// UUID sync_id mapping, soft-delete tombstones, and sync mutex locking.

import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'package:kairos/core/scheduler/scheduler_provider.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/timezone_service.dart';

enum SyncStatus { idle, syncing, success, error }

class SupabaseSyncState {
  final SyncStatus status;
  final DateTime? lastSyncTime;
  final String? errorMessage;
  final int lastSyncedCount;

  const SupabaseSyncState({
    this.status = SyncStatus.idle,
    this.lastSyncTime,
    this.errorMessage,
    this.lastSyncedCount = 0,
  });

  SupabaseSyncState copyWith({
    SyncStatus? status,
    DateTime? lastSyncTime,
    String? errorMessage,
    int? lastSyncedCount,
  }) {
    return SupabaseSyncState(
      status: status ?? this.status,
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      errorMessage: errorMessage,
      lastSyncedCount: lastSyncedCount ?? this.lastSyncedCount,
    );
  }
}

class SupabaseSyncService extends StateNotifier<SupabaseSyncState> {
  final AppDatabase _db;
  final SettingsState _settings;
  static const _uuid = Uuid();

  // Concurrency Mutex
  bool _isSyncing = false;
  bool _hasPendingSync = false;

  SupabaseSyncService(this._db, this._settings) : super(const SupabaseSyncState());

  bool get isConfigured => _settings.isSupabaseConfigured;

  @visibleForTesting
  String get cleanBaseUrl => _cleanBaseUrl;

  @visibleForTesting
  String humanReadableError(String raw) => _humanReadableError(raw);

  String get _cleanBaseUrl {
    var raw = _settings.supabaseUrl.trim();
    raw = raw.replaceAll(RegExp(r'/+$'), '');
    if (raw.endsWith('/rest/v1')) {
      raw = raw.substring(0, raw.length - '/rest/v1'.length);
    } else if (raw.endsWith('/rest')) {
      raw = raw.substring(0, raw.length - '/rest'.length);
    }
    final dashboardMatch = RegExp(r'supabase\.com/dashboard/project/([a-zA-Z0-9_-]+)').firstMatch(raw);
    if (dashboardMatch != null) {
      final projectRef = dashboardMatch.group(1);
      raw = 'https://$projectRef.supabase.co';
    }
    return raw.replaceAll(RegExp(r'/+$'), '');
  }

  Map<String, String> get _headers => {
        'apikey': _settings.supabasePublishableKey.trim(),
        'Authorization': 'Bearer ${_settings.supabasePublishableKey.trim()}',
        'Content-Type': 'application/json',
        'Prefer': 'resolution=merge-duplicates,return=representation',
      };

  /// Triggers a manual or automatic synchronization pass.
  /// Uses a mutex to prevent race conditions from concurrent calls.
  Future<bool> syncNow() async {
    if (!isConfigured) {
      state = state.copyWith(
        status: SyncStatus.error,
        errorMessage: 'Supabase URL or Publishable Key is not configured.',
      );
      return false;
    }

    if (_isSyncing) {
      _hasPendingSync = true;
      return true;
    }

    _isSyncing = true;
    state = state.copyWith(status: SyncStatus.syncing, errorMessage: null);

    try {
      final totalRecords = await _performSync();
      state = state.copyWith(
        status: SyncStatus.success,
        lastSyncTime: DateTime.now(),
        lastSyncedCount: totalRecords,
        errorMessage: null,
      );
      return true;
    } catch (e, stack) {
      debugPrint('[SupabaseSync] Error: $e\n$stack');
      state = state.copyWith(
        status: SyncStatus.error,
        errorMessage: _humanReadableError(e.toString()),
      );
      return false;
    } finally {
      _isSyncing = false;
      if (_hasPendingSync) {
        _hasPendingSync = false;
        syncNow();
      }
    }
  }

  String _humanReadableError(String raw) {
    if (raw.contains('PGRST125') ||
        raw.contains('PGRST204') ||
        raw.contains('Invalid path specified') ||
        raw.contains('Could not find the') ||
        raw.contains('does not exist') ||
        raw.contains('42P01') ||
        raw.contains('404')) {
      return 'Supabase database tables or columns missing (PGRST204/125). Please click "SQL Setup" in Settings and run the updated SQL script in your Supabase SQL Editor.';
    }
    if (raw.contains('42501') || raw.contains('permission denied')) {
      return 'Database permission denied (42501). Please click "SQL Setup" in Settings and run the updated SQL script in your Supabase SQL Editor to grant table privileges.';
    }
    if (raw.contains('401') || raw.contains('Invalid API key') || raw.contains('JWT') || raw.contains('PGRST301')) {
      return 'Authentication failed. Please verify your Supabase Project URL and Publishable Key.';
    }
    if (raw.contains('Failed host lookup') || raw.contains('ClientException')) {
      return 'Network connection error. Check your internet connection or Supabase URL.';
    }
    return raw.replaceAll('Exception: ', '');
  }

  /// Core bidirectional synchronization logic
  Future<int> _performSync() async {
    int count = 0;

    // 1. Ensure all local records have a unique syncId before pushing
    await _ensureLocalSyncIds();
    await _db.habitDao.deduplicateDailyHabitLogs();

    // 2. Categories
    count += await _syncCategories();

    // 3. Events
    count += await _syncEvents();

    // 4. Tasks & Subtasks
    count += await _syncTasks();
    count += await _syncSubtasks();

    // 5. Habits & Habit Logs
    count += await _syncHabits();
    count += await _syncHabitLogs();

    // 6. Holidays
    count += await _syncHolidays();

    return count;
  }

  Future<void> _ensureLocalSyncIds() async {
    // Categories
    final categories = await _db.select(_db.categories).get();
    for (final c in categories) {
      if (c.syncId == null || c.syncId!.isEmpty) {
        await (_db.update(_db.categories)..where((tbl) => tbl.id.equals(c.id))).write(
          CategoriesCompanion(syncId: Value(_uuid.v4())),
        );
      }
    }

    // Events
    final events = await _db.select(_db.events).get();
    for (final e in events) {
      if (e.syncId == null || e.syncId!.isEmpty) {
        await (_db.update(_db.events)..where((tbl) => tbl.id.equals(e.id))).write(
          EventsCompanion(syncId: Value(_uuid.v4())),
        );
      }
    }

    // Tasks
    final tasks = await _db.select(_db.tasks).get();
    for (final t in tasks) {
      if (t.syncId == null || t.syncId!.isEmpty) {
        await (_db.update(_db.tasks)..where((tbl) => tbl.id.equals(t.id))).write(
          TasksCompanion(syncId: Value(_uuid.v4())),
        );
      }
    }

    // Subtasks
    final subtasks = await _db.select(_db.subtasks).get();
    for (final s in subtasks) {
      if (s.syncId == null || s.syncId!.isEmpty) {
        await (_db.update(_db.subtasks)..where((tbl) => tbl.id.equals(s.id))).write(
          SubtasksCompanion(syncId: Value(_uuid.v4())),
        );
      }
    }

    // Habits
    final habits = await _db.select(_db.habits).get();
    for (final h in habits) {
      if (h.syncId == null || h.syncId!.isEmpty) {
        await (_db.update(_db.habits)..where((tbl) => tbl.id.equals(h.id))).write(
          HabitsCompanion(syncId: Value(_uuid.v4())),
        );
      }
    }

    // HabitLogs
    final habitLogs = await _db.select(_db.habitLogs).get();
    for (final l in habitLogs) {
      if (l.syncId == null || l.syncId!.isEmpty) {
        await (_db.update(_db.habitLogs)..where((tbl) => tbl.id.equals(l.id))).write(
          HabitLogsCompanion(syncId: Value(_uuid.v4())),
        );
      }
    }

    // Holidays
    final holidays = await _db.select(_db.holidays).get();
    for (final h in holidays) {
      if (h.syncId == null || h.syncId!.isEmpty) {
        await (_db.update(_db.holidays)..where((tbl) => tbl.id.equals(h.id))).write(
          HolidaysCompanion(syncId: Value(_uuid.v4())),
        );
      }
    }
  }

  // ── 1. CATEGORIES SYNC ─────────────────────────────────────────────
  Future<int> _syncCategories() async {
    final url = Uri.parse('$_cleanBaseUrl/rest/v1/categories?select=*');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode >= 400) {
      throw Exception('Categories sync failed (${response.statusCode}): ${response.body}');
    }

    final List<dynamic> remoteList = jsonDecode(response.body);
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final item in remoteList) {
      final syncId = item['sync_id'] as String?;
      if (syncId != null) remoteMap[syncId] = Map<String, dynamic>.from(item);
    }

    final localList = await _db.select(_db.categories).get();
    final localMap = {for (final l in localList) l.syncId!: l};
    final toPush = <Map<String, dynamic>>[];

    await _db.transaction(() async {
      // Pull remote changes
      for (final remote in remoteMap.values) {
        final syncId = remote['sync_id'] as String;
        final remoteUpdatedAt = DateTime.parse(remote['updated_at'] as String);
        final local = localMap[syncId];

        if (local == null) {
          // Check if category with same slug already exists locally
          final existingSlug = await (_db.select(_db.categories)
                ..where((tbl) => tbl.slug.equals(remote['slug'] as String)))
              .getSingleOrNull();

          if (existingSlug != null) {
            await (_db.update(_db.categories)..where((tbl) => tbl.id.equals(existingSlug.id))).write(
              CategoriesCompanion(
                syncId: Value(syncId),
                name: Value(remote['name'] as String),
                emoji: Value(remote['emoji'] as String? ?? '📌'),
                colorHex: Value(remote['color_hex'] as String? ?? '#4A90D9'),
                isSystem: Value(remote['is_system'] as bool? ?? false),
                isDeleted: Value(remote['is_deleted'] as bool? ?? false),
                updatedAt: Value(remoteUpdatedAt),
              ),
            );
          } else {
            await _db.into(_db.categories).insert(
                  CategoriesCompanion.insert(
                    syncId: Value(syncId),
                    name: remote['name'] as String,
                    slug: remote['slug'] as String,
                    emoji: Value(remote['emoji'] as String? ?? '📌'),
                    colorHex: Value(remote['color_hex'] as String? ?? '#4A90D9'),
                    isSystem: Value(remote['is_system'] as bool? ?? false),
                    isDeleted: Value(remote['is_deleted'] as bool? ?? false),
                    createdAt: Value(DateTime.parse(remote['created_at'] as String)),
                    updatedAt: Value(remoteUpdatedAt),
                  ),
                );
          }
        } else if (remoteUpdatedAt.isAfter(local.updatedAt)) {
          // Remote is newer (LWW)
          await (_db.update(_db.categories)..where((tbl) => tbl.id.equals(local.id))).write(
            CategoriesCompanion(
              name: Value(remote['name'] as String),
              emoji: Value(remote['emoji'] as String? ?? '📌'),
              colorHex: Value(remote['color_hex'] as String? ?? '#4A90D9'),
              isSystem: Value(remote['is_system'] as bool? ?? false),
              isDeleted: Value(remote['is_deleted'] as bool? ?? false),
              updatedAt: Value(remoteUpdatedAt),
            ),
          );
        }
      }

      // Check which locals need pushing
      for (final local in localList) {
        final remote = remoteMap[local.syncId!];
        if (remote == null || local.updatedAt.isAfter(DateTime.parse(remote['updated_at'] as String))) {
          toPush.add({
            'sync_id': local.syncId,
            'name': local.name,
            'slug': local.slug,
            'emoji': local.emoji,
            'color_hex': local.colorHex,
            'is_system': local.isSystem,
            'is_deleted': local.isDeleted,
            'created_at': local.createdAt.toIso8601String(),
            'updated_at': local.updatedAt.toIso8601String(),
          });
        }
      }
    });

    if (toPush.isNotEmpty) {
      final pushUrl = Uri.parse('$_cleanBaseUrl/rest/v1/categories');
      final pushRes = await http.post(pushUrl, headers: _headers, body: jsonEncode(toPush));
      if (pushRes.statusCode >= 400) {
        throw Exception('Push categories failed (${pushRes.statusCode}): ${pushRes.body}');
      }
    }

    return remoteMap.length + toPush.length;
  }

  // ── 2. EVENTS SYNC ─────────────────────────────────────────────────
  Future<int> _syncEvents() async {
    final url = Uri.parse('$_cleanBaseUrl/rest/v1/events?select=*');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode >= 400) {
      throw Exception('Events sync failed (${response.statusCode}): ${response.body}');
    }

    final List<dynamic> remoteList = jsonDecode(response.body);
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final item in remoteList) {
      final syncId = item['sync_id'] as String?;
      if (syncId != null) remoteMap[syncId] = Map<String, dynamic>.from(item);
    }

    final localList = await _db.select(_db.events).get();
    final localMap = {for (final l in localList) l.syncId!: l};
    final toPush = <Map<String, dynamic>>[];

    await _db.transaction(() async {
      for (final remote in remoteMap.values) {
        final syncId = remote['sync_id'] as String;
        final remoteUpdatedAt = DateTime.parse(remote['updated_at'] as String);
        final local = localMap[syncId];

        if (local == null) {
          await _db.into(_db.events).insert(
                EventsCompanion.insert(
                  syncId: Value(syncId),
                  title: remote['title'] as String,
                  category: Value(remote['category'] as String? ?? 'other'),
                  eventType: Value(remote['event_type'] as String?),
                  startTime: TimezoneService.instance.parseRemoteTimestamp(remote['start_time'] as String),
                  endTime: TimezoneService.instance.parseRemoteTimestamp(remote['end_time'] as String),
                  isRecurring: Value(remote['is_recurring'] as bool? ?? false),
                  rrule: Value(remote['rrule'] as String?),
                  requiresPrep: Value(remote['requires_prep'] as bool? ?? false),
                  prepMinutes: Value(remote['prep_minutes'] as int?),
                  isAutoScheduled: Value(remote['is_auto_scheduled'] as bool? ?? false),
                  autoScheduleSource: Value(remote['auto_schedule_source'] as String?),
                  notes: Value(remote['notes'] as String?),
                  isDeleted: Value(remote['is_deleted'] as bool? ?? false),
                  createdAt: Value(DateTime.parse(remote['created_at'] as String)),
                  updatedAt: Value(remoteUpdatedAt),
                ),
              );
        } else if (remoteUpdatedAt.isAfter(local.updatedAt)) {
          await (_db.update(_db.events)..where((tbl) => tbl.id.equals(local.id))).write(
            EventsCompanion(
              title: Value(remote['title'] as String),
              category: Value(remote['category'] as String? ?? 'other'),
              eventType: Value(remote['event_type'] as String?),
              startTime: Value(TimezoneService.instance.parseRemoteTimestamp(remote['start_time'] as String)),
              endTime: Value(TimezoneService.instance.parseRemoteTimestamp(remote['end_time'] as String)),
              isRecurring: Value(remote['is_recurring'] as bool? ?? false),
              rrule: Value(remote['rrule'] as String?),
              requiresPrep: Value(remote['requires_prep'] as bool? ?? false),
              prepMinutes: Value(remote['prep_minutes'] as int?),
              isAutoScheduled: Value(remote['is_auto_scheduled'] as bool? ?? false),
              autoScheduleSource: Value(remote['auto_schedule_source'] as String?),
              notes: Value(remote['notes'] as String?),
              isDeleted: Value(remote['is_deleted'] as bool? ?? false),
              updatedAt: Value(remoteUpdatedAt),
            ),
          );
        }
      }

      for (final local in localList) {
        final remote = remoteMap[local.syncId!];
        if (remote == null || local.updatedAt.isAfter(DateTime.parse(remote['updated_at'] as String))) {
          toPush.add({
            'sync_id': local.syncId,
            'title': local.title,
            'category': local.category,
            'event_type': local.eventType,
            'start_time': TimezoneService.instance.formatForRemoteSync(local.startTime),
            'end_time': TimezoneService.instance.formatForRemoteSync(local.endTime),
            'is_recurring': local.isRecurring,
            'rrule': local.rrule,
            'requires_prep': local.requiresPrep,
            'prep_minutes': local.prepMinutes,
            'is_auto_scheduled': local.isAutoScheduled,
            'auto_schedule_source': local.autoScheduleSource,
            'notes': local.notes,
            'is_deleted': local.isDeleted,
            'created_at': local.createdAt.toIso8601String(),
            'updated_at': local.updatedAt.toIso8601String(),
          });
        }
      }
    });

    if (toPush.isNotEmpty) {
      final pushUrl = Uri.parse('$_cleanBaseUrl/rest/v1/events');
      final pushRes = await http.post(pushUrl, headers: _headers, body: jsonEncode(toPush));
      if (pushRes.statusCode >= 400) {
        throw Exception('Push events failed (${pushRes.statusCode}): ${pushRes.body}');
      }
    }

    return remoteMap.length + toPush.length;
  }

  // ── 3. TASKS SYNC ──────────────────────────────────────────────────
  Future<int> _syncTasks() async {
    final url = Uri.parse('$_cleanBaseUrl/rest/v1/tasks?select=*');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode >= 400) {
      throw Exception('Tasks sync failed (${response.statusCode}): ${response.body}');
    }

    final List<dynamic> remoteList = jsonDecode(response.body);
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final item in remoteList) {
      final syncId = item['sync_id'] as String?;
      if (syncId != null) remoteMap[syncId] = Map<String, dynamic>.from(item);
    }

    final localList = await _db.select(_db.tasks).get();
    final localMap = {for (final l in localList) l.syncId!: l};
    final toPush = <Map<String, dynamic>>[];

    await _db.transaction(() async {
      for (final remote in remoteMap.values) {
        final syncId = remote['sync_id'] as String;
        final remoteUpdatedAt = DateTime.parse(remote['updated_at'] as String);
        final local = localMap[syncId];

        if (local == null) {
          await _db.into(_db.tasks).insert(
                TasksCompanion.insert(
                  syncId: Value(syncId),
                  title: remote['title'] as String,
                  category: Value(remote['category'] as String? ?? 'other'),
                  description: Value(remote['description'] as String?),
                  dueDate: TimezoneService.instance.parseRemoteTimestamp(remote['due_date'] as String),
                  estimatedMinutes: Value(remote['estimated_minutes'] as int?),
                  priority: Value(remote['priority'] as int? ?? 3),
                  isRecurring: Value(remote['is_recurring'] as bool? ?? false),
                  rrule: Value(remote['rrule'] as String?),
                  isCompleted: Value(remote['is_completed'] as bool? ?? false),
                  completedAt: Value(remote['completed_at'] != null ? TimezoneService.instance.parseRemoteTimestamp(remote['completed_at'] as String) : null),
                  isDeleted: Value(remote['is_deleted'] as bool? ?? false),
                  createdAt: Value(DateTime.parse(remote['created_at'] as String)),
                  updatedAt: Value(remoteUpdatedAt),
                ),
              );
        } else if (remoteUpdatedAt.isAfter(local.updatedAt)) {
          await (_db.update(_db.tasks)..where((tbl) => tbl.id.equals(local.id))).write(
            TasksCompanion(
              title: Value(remote['title'] as String),
              category: Value(remote['category'] as String? ?? 'other'),
              description: Value(remote['description'] as String?),
              dueDate: Value(TimezoneService.instance.parseRemoteTimestamp(remote['due_date'] as String)),
              estimatedMinutes: Value(remote['estimated_minutes'] as int?),
              priority: Value(remote['priority'] as int? ?? 3),
              isRecurring: Value(remote['is_recurring'] as bool? ?? false),
              rrule: Value(remote['rrule'] as String?),
              isCompleted: Value(remote['is_completed'] as bool? ?? false),
              completedAt: Value(remote['completed_at'] != null ? TimezoneService.instance.parseRemoteTimestamp(remote['completed_at'] as String) : null),
              isDeleted: Value(remote['is_deleted'] as bool? ?? false),
              updatedAt: Value(remoteUpdatedAt),
            ),
          );
        }
      }

      for (final local in localList) {
        final remote = remoteMap[local.syncId!];
        if (remote == null || local.updatedAt.isAfter(DateTime.parse(remote['updated_at'] as String))) {
          toPush.add({
            'sync_id': local.syncId,
            'title': local.title,
            'category': local.category,
            'description': local.description,
            'due_date': TimezoneService.instance.formatForRemoteSync(local.dueDate),
            'estimated_minutes': local.estimatedMinutes,
            'priority': local.priority,
            'is_recurring': local.isRecurring,
            'rrule': local.rrule,
            'is_completed': local.isCompleted,
            'completed_at': local.completedAt != null ? TimezoneService.instance.formatForRemoteSync(local.completedAt!) : null,
            'is_deleted': local.isDeleted,
            'created_at': local.createdAt.toIso8601String(),
            'updated_at': local.updatedAt.toIso8601String(),
          });
        }
      }
    });

    if (toPush.isNotEmpty) {
      final pushUrl = Uri.parse('$_cleanBaseUrl/rest/v1/tasks');
      final pushRes = await http.post(pushUrl, headers: _headers, body: jsonEncode(toPush));
      if (pushRes.statusCode >= 400) {
        throw Exception('Push tasks failed (${pushRes.statusCode}): ${pushRes.body}');
      }
    }

    return remoteMap.length + toPush.length;
  }

  // ── 4. SUBTASKS SYNC ───────────────────────────────────────────────
  Future<int> _syncSubtasks() async {
    final url = Uri.parse('$_cleanBaseUrl/rest/v1/subtasks?select=*');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode >= 400) {
      throw Exception('Subtasks sync failed (${response.statusCode}): ${response.body}');
    }

    final List<dynamic> remoteList = jsonDecode(response.body);
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final item in remoteList) {
      final syncId = item['sync_id'] as String?;
      if (syncId != null) remoteMap[syncId] = Map<String, dynamic>.from(item);
    }

    final localList = await _db.select(_db.subtasks).get();
    final localMap = {for (final l in localList) l.syncId!: l};
    final toPush = <Map<String, dynamic>>[];

    // Map parent tasks by syncId -> local int id
    final allTasks = await _db.select(_db.tasks).get();
    final taskSyncIdToLocalId = {for (final t in allTasks) t.syncId!: t.id};
    final taskLocalIdToSyncId = {for (final t in allTasks) t.id: t.syncId!};

    await _db.transaction(() async {
      for (final remote in remoteMap.values) {
        final syncId = remote['sync_id'] as String;
        final taskSyncId = remote['task_sync_id'] as String?;
        if (taskSyncId == null || !taskSyncIdToLocalId.containsKey(taskSyncId)) {
          continue; // Parent task not found locally
        }

        final parentTaskId = taskSyncIdToLocalId[taskSyncId]!;
        final local = localMap[syncId];
        final remoteUpdatedAt = remote['updated_at'] != null
            ? DateTime.parse(remote['updated_at'] as String)
            : DateTime.parse(remote['created_at'] as String);

        if (local == null) {
          await _db.into(_db.subtasks).insert(
                SubtasksCompanion.insert(
                  syncId: Value(syncId),
                  taskId: parentTaskId,
                  title: remote['title'] as String,
                  isCompleted: Value(remote['is_completed'] as bool? ?? false),
                  isDeleted: Value(remote['is_deleted'] as bool? ?? false),
                  createdAt: Value(DateTime.parse(remote['created_at'] as String)),
                  updatedAt: Value(remoteUpdatedAt),
                ),
              );
        } else if (remoteUpdatedAt.isAfter(local.updatedAt)) {
          await (_db.update(_db.subtasks)..where((tbl) => tbl.id.equals(local.id))).write(
            SubtasksCompanion(
              title: Value(remote['title'] as String),
              isCompleted: Value(remote['is_completed'] as bool? ?? false),
              isDeleted: Value(remote['is_deleted'] as bool? ?? false),
              updatedAt: Value(remoteUpdatedAt),
            ),
          );
        }
      }

      for (final local in localList) {
        final parentSyncId = taskLocalIdToSyncId[local.taskId];
        if (parentSyncId == null) continue;

        final remote = remoteMap[local.syncId!];
        if (remote == null || local.updatedAt.isAfter(DateTime.parse(remote['updated_at'] ?? remote['created_at']))) {
          toPush.add({
            'sync_id': local.syncId,
            'task_sync_id': parentSyncId,
            'title': local.title,
            'is_completed': local.isCompleted,
            'is_deleted': local.isDeleted,
            'created_at': local.createdAt.toIso8601String(),
            'updated_at': local.updatedAt.toIso8601String(),
          });
        }
      }
    });

    if (toPush.isNotEmpty) {
      final pushUrl = Uri.parse('$_cleanBaseUrl/rest/v1/subtasks');
      final pushRes = await http.post(pushUrl, headers: _headers, body: jsonEncode(toPush));
      if (pushRes.statusCode >= 400) {
        throw Exception('Push subtasks failed (${pushRes.statusCode}): ${pushRes.body}');
      }
    }

    return remoteMap.length + toPush.length;
  }

  // ── 5. HABITS SYNC ─────────────────────────────────────────────────
  Future<int> _syncHabits() async {
    final url = Uri.parse('$_cleanBaseUrl/rest/v1/habits?select=*');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode >= 400) {
      throw Exception('Habits sync failed (${response.statusCode}): ${response.body}');
    }

    final List<dynamic> remoteList = jsonDecode(response.body);
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final item in remoteList) {
      final syncId = item['sync_id'] as String?;
      if (syncId != null) remoteMap[syncId] = Map<String, dynamic>.from(item);
    }

    final localList = await _db.select(_db.habits).get();
    final localMap = {for (final l in localList) l.syncId!: l};
    final toPush = <Map<String, dynamic>>[];

    await _db.transaction(() async {
      for (final remote in remoteMap.values) {
        final syncId = remote['sync_id'] as String;
        final remoteUpdatedAt = DateTime.parse(remote['updated_at'] as String);
        final local = localMap[syncId];

        if (local == null) {
          await _db.into(_db.habits).insert(
                HabitsCompanion.insert(
                  syncId: Value(syncId),
                  title: remote['title'] as String,
                  category: Value(remote['category'] as String? ?? 'personal'),
                  description: Value(remote['description'] as String?),
                  targetFrequencyPerWeek: Value(remote['frequency_per_week'] as int? ?? 1),
                  minSessionMinutes: Value(remote['min_session_minutes'] as int? ?? 30),
                  maxSessionMinutes: Value(remote['max_session_minutes'] as int? ?? 60),
                  preferredWindow: Value(remote['preferred_time_of_day'] as String? ?? 'any'),
                  daysFilter: Value(remote['days_filter'] as String? ?? 'all'),
                  isActive: Value(remote['is_active'] as bool? ?? true),
                  isDeleted: Value(remote['is_deleted'] as bool? ?? false),
                  createdAt: Value(DateTime.parse(remote['created_at'] as String)),
                  updatedAt: Value(remoteUpdatedAt),
                ),
              );
        } else if (remoteUpdatedAt.isAfter(local.updatedAt)) {
          await (_db.update(_db.habits)..where((tbl) => tbl.id.equals(local.id))).write(
            HabitsCompanion(
              title: Value(remote['title'] as String),
              category: Value(remote['category'] as String? ?? 'personal'),
              description: Value(remote['description'] as String?),
              targetFrequencyPerWeek: Value(remote['frequency_per_week'] as int? ?? 1),
              preferredWindow: Value(remote['preferred_time_of_day'] as String? ?? 'any'),
              daysFilter: Value(remote['days_filter'] as String? ?? 'all'),
              isActive: Value(remote['is_active'] as bool? ?? true),
              isDeleted: Value(remote['is_deleted'] as bool? ?? false),
              updatedAt: Value(remoteUpdatedAt),
            ),
          );
        }
      }

      for (final local in localList) {
        final remote = remoteMap[local.syncId!];
        if (remote == null || local.updatedAt.isAfter(DateTime.parse(remote['updated_at'] as String))) {
          toPush.add({
            'sync_id': local.syncId,
            'title': local.title,
            'category': local.category,
            'description': local.description,
            'frequency_per_week': local.targetFrequencyPerWeek,
            'min_session_minutes': local.minSessionMinutes,
            'max_session_minutes': local.maxSessionMinutes,
            'preferred_time_of_day': local.preferredWindow,
            'days_filter': local.daysFilter,
            'is_active': local.isActive,
            'is_deleted': local.isDeleted,
            'created_at': local.createdAt.toIso8601String(),
            'updated_at': local.updatedAt.toIso8601String(),
          });
        }
      }
    });

    if (toPush.isNotEmpty) {
      final pushUrl = Uri.parse('$_cleanBaseUrl/rest/v1/habits');
      final pushRes = await http.post(pushUrl, headers: _headers, body: jsonEncode(toPush));
      if (pushRes.statusCode >= 400) {
        throw Exception('Push habits failed (${pushRes.statusCode}): ${pushRes.body}');
      }
    }

    return remoteMap.length + toPush.length;
  }

  // ── 6. HABIT LOGS SYNC ─────────────────────────────────────────────
  Future<int> _syncHabitLogs() async {
    final url = Uri.parse('$_cleanBaseUrl/rest/v1/habit_logs?select=*');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode >= 400) {
      throw Exception('Habit logs sync failed (${response.statusCode}): ${response.body}');
    }

    final List<dynamic> remoteList = jsonDecode(response.body);
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final item in remoteList) {
      final syncId = item['sync_id'] as String?;
      if (syncId != null) remoteMap[syncId] = Map<String, dynamic>.from(item);
    }

    final localList = await _db.select(_db.habitLogs).get();
    final localMap = {for (final l in localList) l.syncId!: l};
    final toPush = <Map<String, dynamic>>[];

    final allHabits = await _db.select(_db.habits).get();
    final habitSyncIdToLocalId = {for (final h in allHabits) h.syncId!: h.id};
    final habitLocalIdToSyncId = {for (final h in allHabits) h.id: h.syncId!};

    await _db.transaction(() async {
      for (final remote in remoteMap.values) {
        final syncId = remote['sync_id'] as String;
        final habitSyncId = remote['habit_sync_id'] as String?;
        if (habitSyncId == null || !habitSyncIdToLocalId.containsKey(habitSyncId)) {
          continue; // Parent habit not found locally
        }

        final parentHabitId = habitSyncIdToLocalId[habitSyncId]!;
        final local = localMap[syncId];
        final remoteUpdatedAt = remote['updated_at'] != null
            ? DateTime.parse(remote['updated_at'] as String)
            : DateTime.parse(remote['created_at'] as String);
        final remoteIsDeleted = remote['is_deleted'] as bool? ?? false;

        if (local == null) {
          await _db.into(_db.habitLogs).insert(
                HabitLogsCompanion.insert(
                  syncId: Value(syncId),
                  habitId: parentHabitId,
                  completedAt: TimezoneService.instance.parseRemoteTimestamp(remote['completed_at'] as String),
                  durationMinutes: Value(remote['duration_minutes'] as int?),
                  notes: Value(remote['notes'] as String?),
                  isDeleted: Value(remoteIsDeleted),
                  createdAt: Value(DateTime.parse(remote['created_at'] as String)),
                  updatedAt: Value(remoteUpdatedAt),
                ),
              );
        } else if (remoteUpdatedAt.isAfter(local.updatedAt)) {
          await (_db.update(_db.habitLogs)..where((tbl) => tbl.id.equals(local.id))).write(
            HabitLogsCompanion(
              completedAt: Value(TimezoneService.instance.parseRemoteTimestamp(remote['completed_at'] as String)),
              durationMinutes: Value(remote['duration_minutes'] as int?),
              notes: Value(remote['notes'] as String?),
              isDeleted: Value(remoteIsDeleted),
              updatedAt: Value(remoteUpdatedAt),
            ),
          );
        }
      }

      for (final local in localList) {
        final parentSyncId = habitLocalIdToSyncId[local.habitId];
        if (parentSyncId == null) continue;

        final remote = remoteMap[local.syncId!];
        if (remote == null || local.updatedAt.isAfter(DateTime.parse(remote['updated_at'] ?? remote['created_at']))) {
          toPush.add({
            'sync_id': local.syncId,
            'habit_sync_id': parentSyncId,
            'completed_at': TimezoneService.instance.formatForRemoteSync(local.completedAt),
            'duration_minutes': local.durationMinutes,
            'notes': local.notes,
            'is_deleted': local.isDeleted,
            'created_at': local.createdAt.toIso8601String(),
            'updated_at': local.updatedAt.toIso8601String(),
          });
        }
      }
    });

    if (toPush.isNotEmpty) {
      final pushUrl = Uri.parse('$_cleanBaseUrl/rest/v1/habit_logs');
      final pushRes = await http.post(pushUrl, headers: _headers, body: jsonEncode(toPush));
      if (pushRes.statusCode >= 400) {
        throw Exception('Push habit logs failed (${pushRes.statusCode}): ${pushRes.body}');
      }
    }

    return remoteMap.length + toPush.length;
  }

  // ── 7. HOLIDAYS SYNC ───────────────────────────────────────────────
  Future<int> _syncHolidays() async {
    final url = Uri.parse('$_cleanBaseUrl/rest/v1/holidays?select=*');
    final response = await http.get(url, headers: _headers);
    if (response.statusCode >= 400) {
      throw Exception('Holidays sync failed (${response.statusCode}): ${response.body}');
    }

    final List<dynamic> remoteList = jsonDecode(response.body);
    final remoteMap = <String, Map<String, dynamic>>{};
    for (final item in remoteList) {
      final syncId = item['sync_id'] as String?;
      if (syncId != null) remoteMap[syncId] = Map<String, dynamic>.from(item);
    }

    final localList = await _db.select(_db.holidays).get();
    final localMap = {for (final l in localList) l.syncId!: l};
    final toPush = <Map<String, dynamic>>[];

    await _db.transaction(() async {
      for (final remote in remoteMap.values) {
        final syncId = remote['sync_id'] as String;
        final remoteUpdatedAt = DateTime.parse(remote['updated_at'] as String);
        final local = localMap[syncId];

        if (local == null) {
          await _db.into(_db.holidays).insert(
                HolidaysCompanion.insert(
                  syncId: Value(syncId),
                  name: remote['name'] as String,
                  groupName: Value(remote['group_name'] as String? ?? 'US Holidays'),
                  date: TimezoneService.instance.parseRemoteTimestamp(remote['date'] as String),
                  endDate: Value(remote['end_date'] != null ? TimezoneService.instance.parseRemoteTimestamp(remote['end_date'] as String) : null),
                  isEnabled: Value(remote['is_enabled'] as bool? ?? true),
                  isDeleted: Value(remote['is_deleted'] as bool? ?? false),
                  updatedAt: Value(remoteUpdatedAt),
                ),
              );
        } else if (remoteUpdatedAt.isAfter(local.updatedAt)) {
          await (_db.update(_db.holidays)..where((tbl) => tbl.id.equals(local.id))).write(
            HolidaysCompanion(
              name: Value(remote['name'] as String),
              groupName: Value(remote['group_name'] as String? ?? 'US Holidays'),
              date: Value(TimezoneService.instance.parseRemoteTimestamp(remote['date'] as String)),
              endDate: Value(remote['end_date'] != null ? TimezoneService.instance.parseRemoteTimestamp(remote['end_date'] as String) : null),
              isEnabled: Value(remote['is_enabled'] as bool? ?? true),
              isDeleted: Value(remote['is_deleted'] as bool? ?? false),
              updatedAt: Value(remoteUpdatedAt),
            ),
          );
        }
      }

      for (final local in localList) {
        final remote = remoteMap[local.syncId!];
        if (remote == null || local.updatedAt.isAfter(DateTime.parse(remote['updated_at'] as String))) {
          toPush.add({
            'sync_id': local.syncId,
            'name': local.name,
            'group_name': local.groupName,
            'date': TimezoneService.instance.formatForRemoteSync(local.date),
            'end_date': local.endDate != null ? TimezoneService.instance.formatForRemoteSync(local.endDate!) : null,
            'is_enabled': local.isEnabled,
            'is_deleted': local.isDeleted,
            'updated_at': local.updatedAt.toIso8601String(),
          });
        }
      }
    });

    if (toPush.isNotEmpty) {
      final pushUrl = Uri.parse('$_cleanBaseUrl/rest/v1/holidays');
      final pushRes = await http.post(pushUrl, headers: _headers, body: jsonEncode(toPush));
      if (pushRes.statusCode >= 400) {
        throw Exception('Push holidays failed (${pushRes.statusCode}): ${pushRes.body}');
      }
    }

    return remoteMap.length + toPush.length;
  }
}

final supabaseSyncServiceProvider =
    StateNotifierProvider<SupabaseSyncService, SupabaseSyncState>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final settings = ref.watch(settingsNotifierProvider);
  return SupabaseSyncService(db, settings);
});
