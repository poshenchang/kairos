// lib/services/timezone_service.dart
//
// Timezone detection, configuration, and wall-clock serialization service for Kairos.
// Prevents timezone distortion loops and ensures all calendar events and deadlines
// match the user's intended wall-clock schedule across local SQLite and Supabase.

import 'package:drift/drift.dart' show Value;
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/services/settings_service.dart';

class TimezoneOption {
  final int offsetMinutes;
  final String label;

  const TimezoneOption(this.offsetMinutes, this.label);
}

const List<TimezoneOption> kCommonTimezones = [
  TimezoneOption(-720, 'UTC-12:00 (Baker Island)'),
  TimezoneOption(-660, 'UTC-11:00 (Pago Pago, Samoa)'),
  TimezoneOption(-600, 'UTC-10:00 (Honolulu, Hawaii)'),
  TimezoneOption(-540, 'UTC-09:00 (Anchorage, Alaska)'),
  TimezoneOption(-480, 'UTC-08:00 (Los Angeles, Vancouver, PST)'),
  TimezoneOption(-420, 'UTC-07:00 (Denver, Phoenix, MST)'),
  TimezoneOption(-360, 'UTC-06:00 (Chicago, Dallas, Mexico City, CST)'),
  TimezoneOption(-300, 'UTC-05:00 (New York, Toronto, Miami, EST)'),
  TimezoneOption(-240, 'UTC-04:00 (Santiago, Halifax, AST)'),
  TimezoneOption(-210, 'UTC-03:30 (Newfoundland)'),
  TimezoneOption(-180, 'UTC-03:00 (São Paulo, Buenos Aires)'),
  TimezoneOption(-120, 'UTC-02:00 (South Georgia)'),
  TimezoneOption(-60, 'UTC-01:00 (Azores, Cape Verde)'),
  TimezoneOption(0, 'UTC+00:00 (London, Dublin, Lisbon, GMT/UTC)'),
  TimezoneOption(60, 'UTC+01:00 (Paris, Berlin, Rome, Madrid, CET)'),
  TimezoneOption(120, 'UTC+02:00 (Cairo, Athens, Helsinki, EET)'),
  TimezoneOption(180, 'UTC+03:00 (Moscow, Istanbul, Riyadh, Nairobi)'),
  TimezoneOption(210, 'UTC+03:30 (Tehran)'),
  TimezoneOption(240, 'UTC+04:00 (Dubai, Baku, Tbilisi)'),
  TimezoneOption(270, 'UTC+04:30 (Kabul)'),
  TimezoneOption(300, 'UTC+05:00 (Karachi, Tashkent)'),
  TimezoneOption(330, 'UTC+05:30 (New Delhi, Mumbai, Colombo, IST)'),
  TimezoneOption(345, 'UTC+05:45 (Kathmandu)'),
  TimezoneOption(360, 'UTC+06:00 (Dhaka, Almaty)'),
  TimezoneOption(390, 'UTC+06:30 (Yangon)'),
  TimezoneOption(420, 'UTC+07:00 (Bangkok, Jakarta, Hanoi, ICT)'),
  TimezoneOption(480, 'UTC+08:00 (Taipei, Beijing, Singapore, Perth, HK, CST)'),
  TimezoneOption(525, 'UTC+08:45 (Eucla)'),
  TimezoneOption(540, 'UTC+09:00 (Tokyo, Seoul, JST/KST)'),
  TimezoneOption(570, 'UTC+09:30 (Adelaide, Darwin, ACST)'),
  TimezoneOption(600, 'UTC+10:00 (Sydney, Melbourne, Brisbane, AEST)'),
  TimezoneOption(630, 'UTC+10:30 (Lord Howe Island)'),
  TimezoneOption(660, 'UTC+11:00 (Noumea, Solomon Islands)'),
  TimezoneOption(720, 'UTC+12:00 (Auckland, Fiji, NZST)'),
  TimezoneOption(765, 'UTC+12:45 (Chatham Islands)'),
  TimezoneOption(780, 'UTC+13:00 (Samoa, Tonga)'),
  TimezoneOption(840, 'UTC+14:00 (Kiritimati, Line Islands)'),
];

class TimezoneService {
  static final TimezoneService instance = TimezoneService._();
  TimezoneService._();

  /// Returns the current active timezone offset duration.
  /// If [SettingsState.timezoneMode] is 'manual', uses the user-configured offset.
  /// Otherwise auto-detects system timezone offset.
  Duration getActiveOffset([SettingsState? settings]) {
    if (settings != null && settings.timezoneMode == 'manual') {
      return Duration(minutes: settings.manualTimezoneOffsetMinutes);
    }
    return DateTime.now().timeZoneOffset;
  }

  /// Formatted label of the active timezone (either manual or auto-detected).
  String getActiveTimezoneLabel([SettingsState? settings]) {
    if (settings != null && settings.timezoneMode == 'manual') {
      return settings.manualTimezoneName;
    }
    return getDetectedTimezoneLabel();
  }

  /// Formatted label of the detected system timezone (e.g. "UTC+08:00 (CST)")
  String getDetectedTimezoneLabel() {
    final offset = DateTime.now().timeZoneOffset;
    final totalMinutes = offset.inMinutes;
    final sign = totalMinutes >= 0 ? '+' : '-';
    final absMinutes = totalMinutes.abs();
    final hours = (absMinutes ~/ 60).toString().padLeft(2, '0');
    final minutes = (absMinutes % 60).toString().padLeft(2, '0');
    final tzName = DateTime.now().timeZoneName;
    return 'UTC$sign$hours:$minutes${tzName.isNotEmpty ? ' ($tzName)' : ''}';
  }

  /// Converts a UTC [DateTime] into a display [DateTime] matching the active timezone.
  /// The resulting [DateTime] has year, month, day, hour, minute reflecting the user's active timezone.
  DateTime toActiveTime(DateTime dt, [SettingsState? settings]) {
    final utc = dt.isUtc ? dt : dt.toUtc();
    final offset = getActiveOffset(settings);
    final active = utc.add(offset);
    return DateTime(
      active.year,
      active.month,
      active.day,
      active.hour,
      active.minute,
      active.second,
      active.millisecond,
    );
  }

  /// Converts a local wall-clock [DateTime] (picked in the UI in the active timezone)
  /// into an absolute UTC [DateTime] for database and cloud storage.
  DateTime fromActiveTime(DateTime wallClock, [SettingsState? settings]) {
    final offset = getActiveOffset(settings);
    return DateTime.utc(
      wallClock.year,
      wallClock.month,
      wallClock.day,
      wallClock.hour,
      wallClock.minute,
      wallClock.second,
      wallClock.millisecond,
    ).subtract(offset);
  }

  /// Returns the current time in the active timezone.
  DateTime activeNow([SettingsState? settings]) {
    return toActiveTime(DateTime.now().toUtc(), settings);
  }

  /// Formats a [DateTime] as an absolute UTC ISO 8601 string for cloud storage in Supabase:
  /// e.g. "2026-10-19T01:00:00.000Z"
  String formatForRemoteSync(DateTime dt) {
    final utc = dt.isUtc ? dt : dt.toUtc();
    return utc.toIso8601String();
  }

  /// Parses a remote ISO 8601 timestamp from Supabase into a ground-truth UTC [DateTime].
  DateTime parseRemoteTimestamp(String raw) {
    final str = raw.trim();
    if (str.isEmpty) return DateTime.now().toUtc();

    // If date-only format (e.g. "2026-10-19")
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(str)) {
      final parts = str.split('-').map(int.parse).toList();
      return DateTime.utc(parts[0], parts[1], parts[2]);
    }

    try {
      final parsed = DateTime.parse(str);
      return parsed.toUtc();
    } catch (_) {
      return DateTime.now().toUtc();
    }
  }

  /// Re-aligns all existing events and tasks by shifting their timestamps by [offset].
  /// Useful to repair timetable schedules that were shifted by +8 hours during previous syncs.
  Future<int> shiftAllEventsAndTasks(AppDatabase db, Duration offset) async {
    int modifiedCount = 0;
    final nowUtc = DateTime.now().toUtc();

    await db.transaction(() async {
      // 1. Shift Events
      final events = await db.eventDao.getAllEvents();
      for (final e in events) {
        if (e.isDeleted) continue;
        await (db.update(db.events)..where((tbl) => tbl.id.equals(e.id))).write(
          EventsCompanion(
            startTime: Value(e.startTime.add(offset)),
            endTime: Value(e.endTime.add(offset)),
            updatedAt: Value(nowUtc),
          ),
        );
        modifiedCount++;
      }

      // 2. Shift Tasks
      final tasks = await db.taskDao.getAllTasks();
      for (final t in tasks) {
        if (t.isDeleted) continue;
        await (db.update(db.tasks)..where((tbl) => tbl.id.equals(t.id))).write(
          TasksCompanion(
            dueDate: Value(t.dueDate.add(offset)),
            completedAt: t.completedAt != null ? Value(t.completedAt!.add(offset)) : const Value.absent(),
            updatedAt: Value(nowUtc),
          ),
        );
        modifiedCount++;
      }
    });

    return modifiedCount;
  }
}
