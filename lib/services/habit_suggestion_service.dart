// lib/services/habit_suggestion_service.dart
//
// Background / lifecycle service to:
// 1. Auto-log habit completion when time passes a scheduled habit session (now > event.endTime).
// 2. Suggest uncompleted and unscheduled daily habits when >= 30m of free time is detected (9am - 10pm).

import 'dart:math';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/services/notification_service.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kLastHabitSuggestionEpochKey = 'kairos_last_habit_suggestion_epoch';

class HabitSuggestionService {
  static final HabitSuggestionService instance = HabitSuggestionService._();
  HabitSuggestionService._();

  /// Checks for scheduled habit sessions whose end time has passed and logs them.
  /// Uses idempotent notes tags (`auto_event:<eventId>`) to prevent duplicate logs.
  Future<int> autoLogPassedHabits(
    AppDatabase db, {
    NotificationService? notificationService,
    VoidCallback? onLogged,
  }) async {
    final now = DateTime.now();
    final allEvents = await db.eventDao.getAllEvents();

    // Find habit events that ended in the past
    final passedHabitEvents = allEvents.where((e) {
      if (e.isDeleted) return false;
      final source = e.autoScheduleSource;
      if (source == null || !source.startsWith('habit:')) return false;
      return e.endTime.isBefore(now);
    }).toList();

    if (passedHabitEvents.isEmpty) return 0;

    int loggedCount = 0;
    for (final event in passedHabitEvents) {
      final source = event.autoScheduleSource!;
      final habitIdStr = source.replaceFirst('habit:', '').split(';').first;
      final habitId = int.tryParse(habitIdStr);
      if (habitId == null) continue;

      // Check if already auto-logged for this specific event
      final existingLogs = await db.habitDao.getLogsForHabit(habitId);
      final alreadyLogged = existingLogs.any((l) => l.notes == 'auto_event:${event.id}');
      if (alreadyLogged) continue;

      final duration = event.endTime.difference(event.startTime).inMinutes;
      await db.habitDao.logHabitCompletion(
        HabitLogsCompanion.insert(
          habitId: habitId,
          completedAt: event.endTime,
          durationMinutes: drift.Value(duration > 0 ? duration : 30),
          notes: drift.Value('auto_event:${event.id}'),
        ),
      );

      loggedCount++;
      debugPrint('[HabitSuggestionService] Auto-logged completion for habit #$habitId from event #${event.id} ("${event.title}")');
    }

    if (loggedCount > 0 && onLogged != null) {
      onLogged();
    }

    return loggedCount;
  }

  /// Suggests an uncompleted and unscheduled daily habit when >= 30 minutes of free time
  /// is detected within the 9:00 AM - 10:00 PM window.
  Future<bool> checkAndSuggestDailyHabit({
    required AppDatabase db,
    required SettingsState settings,
    required NotificationService notificationService,
    bool ignoreCooldown = false,
  }) async {
    // 1. Feature must be enabled in settings
    if (!settings.notificationsEnabled || !settings.suggestHabitsInFreeTime) {
      return false;
    }

    final now = DateTime.now();

    // 2. Must be within 9:00 AM - 10:00 PM (09:00 to 22:00)
    if (now.hour < 9 || now.hour >= 22) {
      return false;
    }

    // 3. Cooldown check (default: at least 90 minutes between suggestions)
    final prefs = await SharedPreferences.getInstance();
    if (!ignoreCooldown) {
      final lastEpoch = prefs.getInt(_kLastHabitSuggestionEpochKey);
      if (lastEpoch != null) {
        final lastTime = DateTime.fromMillisecondsSinceEpoch(lastEpoch);
        if (now.difference(lastTime) < const Duration(minutes: 90)) {
          return false;
        }
      }
    }

    // 4. Query today's events to compute current free time
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final todayEvents = (await db.eventDao.getEventsInRange(todayStart, todayEnd))
        .where((e) => !e.isDeleted && e.eventType != 'reminder')
        .toList();

    // Check if user is currently busy
    final isBusyNow = todayEvents.any((e) => e.startTime.isBefore(now) && e.endTime.isAfter(now));
    if (isBusyNow) return false;

    // Check duration until next event or 10:00 PM cutoff
    final endOfWindow = DateTime(now.year, now.month, now.day, 22, 0);
    final futureEvents = todayEvents.where((e) => e.startTime.isAfter(now)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    DateTime nextEventStart = futureEvents.isNotEmpty ? futureEvents.first.startTime : endOfWindow;
    if (nextEventStart.isAfter(endOfWindow)) {
      nextEventStart = endOfWindow;
    }

    final freeMinutes = nextEventStart.difference(now).inMinutes;
    if (freeMinutes < 30) {
      return false; // Not enough free time (less than 30 mins)
    }

    // 5. Find uncompleted and unscheduled daily habits
    final activeHabits = await db.habitDao.getAllActiveHabits();
    final dailyHabits = activeHabits.where((h) => h.targetFrequencyPerWeek >= 7).toList();
    if (dailyHabits.isEmpty) return false;

    final isWeekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    final candidates = <Habit>[];

    for (final habit in dailyHabits) {
      // Days filter check
      if (habit.daysFilter == 'weekdays' && isWeekend) continue;
      if (habit.daysFilter == 'weekends' && !isWeekend) continue;

      // Check if already scheduled today on the calendar
      final isScheduledToday = todayEvents.any(
        (e) => e.autoScheduleSource != null && e.autoScheduleSource!.contains('habit:${habit.id}'),
      );
      if (isScheduledToday) continue;

      // Check if already completed today
      final logsToday = await db.habitDao.getLogsForHabit(habit.id, from: todayStart, to: todayEnd);
      if (logsToday.isNotEmpty) continue;

      candidates.add(habit);
    }

    if (candidates.isEmpty) return false;

    // 6. Pick one randomly
    final chosen = candidates[Random().nextInt(candidates.length)];

    // 7. Dispatch notification
    await notificationService.showNotification(
      id: 777000 + chosen.id,
      title: 'Free Time Opportunity',
      body: 'You have $freeMinutes minutes of free time right now. How about a session of "${chosen.title}"?',
    );

    await prefs.setInt(_kLastHabitSuggestionEpochKey, now.millisecondsSinceEpoch);
    debugPrint('[HabitSuggestionService] Dispatched suggestion for "${chosen.title}" with $freeMinutes min free');
    return true;
  }

  /// Convenience coordinator to run both auto-log and suggestion checks
  Future<void> runPeriodicChecks({
    required AppDatabase db,
    required SettingsState settings,
    required NotificationService notificationService,
    VoidCallback? onHabitsUpdated,
  }) async {
    await autoLogPassedHabits(db, notificationService: notificationService, onLogged: onHabitsUpdated);
    await checkAndSuggestDailyHabit(
      db: db,
      settings: settings,
      notificationService: notificationService,
    );
  }
}

final habitSuggestionServiceProvider = Provider<HabitSuggestionService>((ref) {
  return HabitSuggestionService.instance;
});
