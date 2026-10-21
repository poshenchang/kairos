// lib/services/form_defaults_service.dart
//
// Caches the last entered date/time/duration/category choices as defaults
// for AddEventDialog, TaskFormSheet, and HabitFormSheet.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FormDefaultsService {
  static final FormDefaultsService instance = FormDefaultsService._();
  FormDefaultsService._();

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  // ── Events ────────────────────────────────────────────────────────────────
  DateTime? get lastEventStartDate {
    final s = _prefs?.getString('last_event_start_date');
    return s != null ? DateTime.tryParse(s) : null;
  }

  TimeOfDay? get lastEventStartTime {
    final h = _prefs?.getInt('last_event_start_hour');
    final m = _prefs?.getInt('last_event_start_minute');
    return h != null && m != null ? TimeOfDay(hour: h, minute: m) : null;
  }

  TimeOfDay? get lastEventEndTime {
    final h = _prefs?.getInt('last_event_end_hour');
    final m = _prefs?.getInt('last_event_end_minute');
    return h != null && m != null ? TimeOfDay(hour: h, minute: m) : null;
  }

  String? get lastEventCategory => _prefs?.getString('last_event_category');

  Future<void> saveEventDefaults({
    required DateTime startDate,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required String category,
  }) async {
    await init();
    await _prefs?.setString('last_event_start_date', startDate.toIso8601String());
    await _prefs?.setInt('last_event_start_hour', startTime.hour);
    await _prefs?.setInt('last_event_start_minute', startTime.minute);
    await _prefs?.setInt('last_event_end_hour', endTime.hour);
    await _prefs?.setInt('last_event_end_minute', endTime.minute);
    await _prefs?.setString('last_event_category', category);
  }

  // ── Tasks ─────────────────────────────────────────────────────────────────
  DateTime? get lastTaskDueDate {
    final s = _prefs?.getString('last_task_due_date');
    return s != null ? DateTime.tryParse(s) : null;
  }

  TimeOfDay? get lastTaskDueTime {
    final h = _prefs?.getInt('last_task_due_hour');
    final m = _prefs?.getInt('last_task_due_minute');
    return h != null && m != null ? TimeOfDay(hour: h, minute: m) : null;
  }

  int? get lastTaskEstimatedMinutes => _prefs?.getInt('last_task_estimated_minutes');
  String? get lastTaskCategory => _prefs?.getString('last_task_category');

  Future<void> saveTaskDefaults({
    required DateTime dueDate,
    required TimeOfDay dueTime,
    required int estimatedMinutes,
    required String category,
  }) async {
    await init();
    await _prefs?.setString('last_task_due_date', dueDate.toIso8601String());
    await _prefs?.setInt('last_task_due_hour', dueTime.hour);
    await _prefs?.setInt('last_task_due_minute', dueTime.minute);
    await _prefs?.setInt('last_task_estimated_minutes', estimatedMinutes);
    await _prefs?.setString('last_task_category', category);
  }

  // ── Habits ────────────────────────────────────────────────────────────────
  TimeOfDay? get lastHabitTime {
    final h = _prefs?.getInt('last_habit_hour');
    final m = _prefs?.getInt('last_habit_minute');
    return h != null && m != null ? TimeOfDay(hour: h, minute: m) : null;
  }

  int? get lastHabitDuration => _prefs?.getInt('last_habit_duration');
  String? get lastHabitCategory => _prefs?.getString('last_habit_category');

  Future<void> saveHabitDefaults({
    required TimeOfDay time,
    required int durationMinutes,
    required String category,
  }) async {
    await init();
    await _prefs?.setInt('last_habit_hour', time.hour);
    await _prefs?.setInt('last_habit_minute', time.minute);
    await _prefs?.setInt('last_habit_duration', durationMinutes);
    await _prefs?.setString('last_habit_category', category);
  }
}

final formDefaultsServiceProvider = Provider<FormDefaultsService>((ref) {
  return FormDefaultsService.instance;
});

