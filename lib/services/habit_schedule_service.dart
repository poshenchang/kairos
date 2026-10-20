// lib/services/habit_schedule_service.dart
//
// Service and state notifier to manage default weekly schedule templates
// for habits, supporting complex weekly routines (e.g. everyday at 8am,
// or Monday night at 8pm and Wednesday noon at 12pm).
// Allows initializing any week with that default schedule.

import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kHabitSchedulesKey = 'kairos_habit_default_schedules';

class HabitDefaultSlot {
  final int weekday; // 1 = Mon, ..., 7 = Sun (Dart standard)
  final int hour;    // 0 - 23
  final int minute;  // 0 - 59
  final int durationMinutes; // e.g. 60

  const HabitDefaultSlot({
    required this.weekday,
    required this.hour,
    required this.minute,
    this.durationMinutes = 60,
  });

  String get weekdayName {
    return switch (weekday) {
      1 => 'Mon',
      2 => 'Tue',
      3 => 'Wed',
      4 => 'Thu',
      5 => 'Fri',
      6 => 'Sat',
      7 => 'Sun',
      _ => 'Day',
    };
  }

  String get timeFormatted {
    final dt = DateTime(2026, 1, 1, hour, minute);
    return DateFormat('h:mm a').format(dt);
  }

  String get summary => '$weekdayName at $timeFormatted (${durationMinutes}m)';

  Map<String, dynamic> toJson() => {
    'weekday': weekday,
    'hour': hour,
    'minute': minute,
    'durationMinutes': durationMinutes,
  };

  factory HabitDefaultSlot.fromJson(Map<String, dynamic> json) => HabitDefaultSlot(
    weekday: json['weekday'] as int,
    hour: json['hour'] as int,
    minute: json['minute'] as int,
    durationMinutes: (json['durationMinutes'] as int?) ?? 60,
  );
}

class HabitScheduleNotifier extends StateNotifier<Map<int, List<HabitDefaultSlot>>> {
  final Ref? _ref;

  HabitScheduleNotifier([this._ref]) : super({}) {
    _load();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    final map = <int, List<HabitDefaultSlot>>{};

    // 1. Load from DB
    if (_ref != null) {
      try {
        final db = _ref!.read(appDatabaseProvider);
        final habits = await (db.select(db.habits)..where((h) => h.isDeleted.equals(false))).get();
        for (final h in habits) {
          if (h.defaultSchedule != null && h.defaultSchedule!.isNotEmpty) {
            try {
              final list = jsonDecode(h.defaultSchedule!) as List<dynamic>;
              map[h.id] = list
                  .map((item) => HabitDefaultSlot.fromJson(item as Map<String, dynamic>))
                  .toList();
            } catch (_) {}
          }
        }
      } catch (_) {}
    }

    // 2. Fallback to SharedPreferences (migrate local legacy templates to DB)
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kHabitSchedulesKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        final db = _ref != null ? _ref!.read(appDatabaseProvider) : null;
        for (final entry in decoded.entries) {
          final habitId = int.tryParse(entry.key);
          if (habitId != null && !map.containsKey(habitId) && entry.value is List) {
            final slots = (entry.value as List)
                .map((item) => HabitDefaultSlot.fromJson(item as Map<String, dynamic>))
                .toList();
            map[habitId] = slots;
            // Write to DB so it syncs across devices
            if (db != null) {
              await (db.update(db.habits)..where((tbl) => tbl.id.equals(habitId))).write(
                HabitsCompanion(
                  defaultSchedule: drift.Value(jsonEncode(slots.map((s) => s.toJson()).toList())),
                  updatedAt: drift.Value(DateTime.now().toUtc()),
                ),
              );
            }
          }
        }
      }
    } catch (_) {}

    state = map;
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{};
    for (final entry in state.entries) {
      map[entry.key.toString()] = entry.value.map((s) => s.toJson()).toList();
    }
    await prefs.setString(_kHabitSchedulesKey, jsonEncode(map));
  }

  List<HabitDefaultSlot> getSlots(int habitId) {
    return state[habitId] ?? [];
  }

  Future<void> setSlots(int habitId, List<HabitDefaultSlot> slots) async {
    final updated = Map<int, List<HabitDefaultSlot>>.from(state);
    if (slots.isEmpty) {
      updated.remove(habitId);
    } else {
      updated[habitId] = slots;
    }
    state = updated;

    // Persist to DB for multi-device sync
    if (_ref != null) {
      try {
        final db = _ref!.read(appDatabaseProvider);
        final jsonStr = slots.isEmpty ? null : jsonEncode(slots.map((s) => s.toJson()).toList());
        await (db.update(db.habits)..where((tbl) => tbl.id.equals(habitId))).write(
          HabitsCompanion(
            defaultSchedule: drift.Value(jsonStr),
            updatedAt: drift.Value(DateTime.now().toUtc()),
          ),
        );
      } catch (_) {}
    }

    await _save();
  }

  /// Saves the current week's scheduled habit events as the default template for [habitId].
  Future<int> saveFromWeekEvents(int habitId, List<Event> weekEvents) async {
    final habitEvents = weekEvents.where((e) => e.autoScheduleSource == 'habit:$habitId').toList();
    if (habitEvents.isEmpty) return 0;

    final slots = habitEvents.map((e) {
      final start = e.startTime.toLocal();
      final end = e.endTime.toLocal();
      final duration = end.difference(start).inMinutes;
      return HabitDefaultSlot(
        weekday: start.weekday,
        hour: start.hour,
        minute: start.minute,
        durationMinutes: duration > 0 ? duration : 60,
      );
    }).toList();

    await setSlots(habitId, slots);
    return slots.length;
  }

  /// Initializes the week starting on [weekSunday] with all active habits' default schedules.
  /// Removes all existing instances of each scheduled habit in that week first, then adds the default schedule.
  /// Returns the number of new events inserted.
  Future<int> populateWeek({
    required DateTime weekSunday,
    required List<Habit> habits,
    required EventDao eventDao,
    List<Event>? existingEvents,
    NotificationService? notificationService,
  }) async {
    int insertedCount = 0;

    // Normalise weekSunday to 00:00:00
    final baseSunday = DateTime(weekSunday.year, weekSunday.month, weekSunday.day);
    final weekEnd = baseSunday.add(const Duration(days: 7));

    // Fetch all non-deleted events to reliably filter by local week range
    final allEvents = await eventDao.getAllEvents();

    for (final habit in habits) {
      if (!habit.isActive) continue;
      final slots = getSlots(habit.id);
      if (slots.isEmpty) continue;

      // 1. Remove all existing instances of that habit in the target week
      // (includes instances in any timeslot, whether in default template or not)
      final habitEventsInWeek = allEvents.where((e) {
        if (e.isDeleted) return false;
        final start = e.startTime.toLocal();
        if (start.isBefore(baseSunday) || !start.isBefore(weekEnd)) return false;

        final src = e.autoScheduleSource;
        final matchesSource = src != null && (
          src == 'habit:${habit.id}' ||
          src.startsWith('habit:${habit.id};') ||
          src.startsWith('habit:${habit.id}:')
        );
        final matchesTitle = e.title.trim().toLowerCase() == habit.title.trim().toLowerCase();

        return matchesSource || (matchesTitle && (e.isAutoScheduled || e.category == habit.category));
      }).toList();

      for (final oldEvent in habitEventsInWeek) {
        await eventDao.deleteEvent(oldEvent.id);
        if (notificationService != null) {
          await notificationService.cancelNotification(oldEvent.id);
        }
      }

      // 2. Insert the default schedule slots
      for (final slot in slots) {
        final daysFromSunday = slot.weekday % 7;
        final targetDate = baseSunday.add(Duration(days: daysFromSunday));
        final start = DateTime(targetDate.year, targetDate.month, targetDate.day, slot.hour, slot.minute);
        final end = start.add(Duration(minutes: slot.durationMinutes));

        final newId = await eventDao.insertEvent(
          EventsCompanion.insert(
            title: habit.title,
            startTime: start,
            endTime: end,
            category: drift.Value(habit.category),
            isAutoScheduled: const drift.Value(true),
            autoScheduleSource: drift.Value('habit:${habit.id}'),
            notes: const drift.Value('Scheduled from habit default schedule'),
          ),
        );
        insertedCount++;

        if (notificationService != null) {
          final newEvent = await eventDao.getEventById(newId);
          if (newEvent != null) {
            notificationService.scheduleEventNotification(newEvent);
          }
        }
      }
    }

    return insertedCount;
  }
}

final habitScheduleProvider =
    StateNotifierProvider<HabitScheduleNotifier, Map<int, List<HabitDefaultSlot>>>(
  (ref) => HabitScheduleNotifier(ref),
);
