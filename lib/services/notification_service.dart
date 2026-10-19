import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:kairos/data/database/app_database.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();

    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Open Kairos',
    );

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      linux: linuxSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    try {
      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (details) {
          debugPrint('Notification clicked: ${details.payload}');
        },
      );
      _isInitialized = true;
    } catch (e) {
      debugPrint('Failed to initialize NotificationService: $e');
    }
  }

  NotificationDetails _buildDetails() {
    const linuxDetails = LinuxNotificationDetails(
      urgency: LinuxNotificationUrgency.normal,
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    return const NotificationDetails(
      linux: linuxDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_isInitialized) await initialize();

    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: _buildDetails(),
        payload: payload,
      );
    } catch (e) {
      debugPrint('Error displaying notification: $e');
    }
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    if (!_isInitialized) await initialize();
    if (scheduledDate.isBefore(DateTime.now())) return;

    try {
      final scheduledTz = tz.TZDateTime.from(scheduledDate, tz.local);
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledTz,
        notificationDetails: _buildDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Fallback to timer for scheduled notification: $e');
      final delay = scheduledDate.difference(DateTime.now());
      if (delay > Duration.zero) {
        Future.delayed(delay, () {
          showNotification(id: id, title: title, body: body, payload: payload);
        });
      }
    }
  }

  Future<void> scheduleEventNotification(Event event) async {
    final source = event.autoScheduleSource;

    // Check if explicitly disabled with notify:none
    if (source != null && source.contains('notify:none')) return;

    final isReminder = event.eventType == 'reminder';
    final isDerived = event.isAutoScheduled ||
        (source != null &&
            (source.startsWith('habit:') ||
                source.startsWith('task:') ||
                source.startsWith('prep:')));

    int? offsetMinutes;

    // Check if notify:<offset> is present in source
    if (source != null) {
      final match = RegExp(r'notify:(\d+)').firstMatch(source);
      if (match != null) {
        offsetMinutes = int.tryParse(match.group(1)!);
      }
    }

    // Default to send reminder at start for derived and reminder events; otherwise default to no reminder
    if (offsetMinutes == null) {
      if (isReminder || isDerived) {
        offsetMinutes = 0; // At start
      } else {
        return; // No reminder by default
      }
    }

    final notifyTime = event.startTime.subtract(Duration(minutes: offsetMinutes));
    if (notifyTime.isBefore(DateTime.now())) return;

    String title;
    String body;
    if (isReminder) {
      title = 'Reminder';
      body = 'Reminder: ${event.title}';
    } else if (source != null && source.startsWith('habit:')) {
      title = 'Habit Session';
      body = offsetMinutes == 0
          ? 'Time for your habit: ${event.title}'
          : 'Habit session in $offsetMinutes min: ${event.title}';
    } else if (source != null && (source.startsWith('task:') || source.contains(':subtask:'))) {
      title = 'Task Session';
      body = offsetMinutes == 0
          ? 'Time to focus on: ${event.title}'
          : 'Task session in $offsetMinutes min: ${event.title}';
    } else if (source != null && source.contains('prep:')) {
      title = 'Prep / Warmup Session';
      body = offsetMinutes == 0
          ? 'Time to prepare for: ${event.title}'
          : 'Prep session in $offsetMinutes min: ${event.title}';
    } else {
      title = 'Upcoming Event';
      body = offsetMinutes == 0
          ? 'Event starting now: ${event.title}'
          : 'Event starting in $offsetMinutes min: ${event.title}';
    }

    await scheduleNotification(
      id: event.id,
      title: title,
      body: body,
      scheduledDate: notifyTime,
    );
  }

  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  Future<void> cancelNotification(int id) => cancel(id);

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService.instance;
});
