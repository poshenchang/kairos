// lib/services/settings_service.dart
//
// Persistent storage for user settings & customizations using SharedPreferences.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/ui/theme/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemeModeKey = 'kairos_theme_mode';
const _kPaletteIdKey = 'kairos_palette_id';
const _kNotificationsEnabledKey = 'kairos_notifications_enabled';
const _kWeekStartsOnSundayKey = 'kairos_week_starts_sunday';
const _kCalendarViewKey = 'kairos_calendar_view_mode';
const _kSuggestHabitsInFreeTimeKey = 'kairos_suggest_habits_free_time';
const _kSupabaseUrlKey = 'kairos_supabase_url';
const _kSupabasePublishableKey = 'kairos_supabase_publishable_key';
const _kTimezoneModeKey = 'kairos_timezone_mode';
const _kManualTimezoneOffsetMinutesKey = 'kairos_manual_timezone_offset_minutes';
const _kManualTimezoneNameKey = 'kairos_manual_timezone_name';

class SettingsState {
  final ThemeMode themeMode;
  final AppPaletteId paletteId;
  final bool notificationsEnabled;
  final bool weekStartsOnSunday;
  final String calendarViewMode; // 'timetable' or 'list'
  final bool suggestHabitsInFreeTime;
  final String supabaseUrl;
  final String supabasePublishableKey;
  final String timezoneMode; // 'auto' or 'manual'
  final int manualTimezoneOffsetMinutes; // e.g. 480 for UTC+8
  final String manualTimezoneName;

  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.paletteId = AppPaletteId.oceanic,
    this.notificationsEnabled = true,
    this.weekStartsOnSunday = true,
    this.calendarViewMode = 'timetable', // Timetable is default as requested!
    this.suggestHabitsInFreeTime = true,
    this.supabaseUrl = '',
    this.supabasePublishableKey = '',
    this.timezoneMode = 'auto',
    this.manualTimezoneOffsetMinutes = 480, // Default to UTC+8
    this.manualTimezoneName = 'UTC+08:00 (Taipei, Beijing, Singapore, Perth, HK, CST)',
  });

  bool get isSupabaseConfigured => supabaseUrl.isNotEmpty && supabasePublishableKey.isNotEmpty;

  SettingsState copyWith({
    ThemeMode? themeMode,
    AppPaletteId? paletteId,
    bool? notificationsEnabled,
    bool? weekStartsOnSunday,
    String? calendarViewMode,
    bool? suggestHabitsInFreeTime,
    String? supabaseUrl,
    String? supabasePublishableKey,
    String? timezoneMode,
    int? manualTimezoneOffsetMinutes,
    String? manualTimezoneName,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      paletteId: paletteId ?? this.paletteId,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      weekStartsOnSunday: weekStartsOnSunday ?? this.weekStartsOnSunday,
      calendarViewMode: calendarViewMode ?? this.calendarViewMode,
      suggestHabitsInFreeTime: suggestHabitsInFreeTime ?? this.suggestHabitsInFreeTime,
      supabaseUrl: supabaseUrl ?? this.supabaseUrl,
      supabasePublishableKey: supabasePublishableKey ?? this.supabasePublishableKey,
      timezoneMode: timezoneMode ?? this.timezoneMode,
      manualTimezoneOffsetMinutes: manualTimezoneOffsetMinutes ?? this.manualTimezoneOffsetMinutes,
      manualTimezoneName: manualTimezoneName ?? this.manualTimezoneName,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final themeModeStr = prefs.getString(_kThemeModeKey);
      final themeMode = switch (themeModeStr) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

      final paletteStr = prefs.getString(_kPaletteIdKey);
      final palette = AppPaletteId.values.firstWhere(
        (p) => p.name == paletteStr,
        orElse: () => AppPaletteId.oceanic,
      );

      final notifs = prefs.getBool(_kNotificationsEnabledKey) ?? true;
      final sunday = prefs.getBool(_kWeekStartsOnSundayKey) ?? true;
      final viewMode = prefs.getString(_kCalendarViewKey) ?? 'timetable';
      final suggestHabits = prefs.getBool(_kSuggestHabitsInFreeTimeKey) ?? true;
      final sbUrl = prefs.getString(_kSupabaseUrlKey) ?? '';
      final sbKey = prefs.getString(_kSupabasePublishableKey) ?? '';
      final tzMode = prefs.getString(_kTimezoneModeKey) ?? 'auto';
      final manualOffset = prefs.getInt(_kManualTimezoneOffsetMinutesKey) ?? 480;
      final manualName = prefs.getString(_kManualTimezoneNameKey) ??
          'UTC+08:00 (Taipei, Beijing, Singapore, Perth, HK, CST)';

      state = SettingsState(
        themeMode: themeMode,
        paletteId: palette,
        notificationsEnabled: notifs,
        weekStartsOnSunday: sunday,
        calendarViewMode: viewMode,
        suggestHabitsInFreeTime: suggestHabits,
        supabaseUrl: sbUrl,
        supabasePublishableKey: sbKey,
        timezoneMode: tzMode,
        manualTimezoneOffsetMinutes: manualOffset,
        manualTimezoneName: manualName,
      );
    } catch (_) {
      // SharedPreferences platform channel not available in unit test environments
    }
  }

  Future<void> setTimezoneConfig({
    required String mode,
    int? manualOffsetMinutes,
    String? manualName,
  }) async {
    state = state.copyWith(
      timezoneMode: mode,
      manualTimezoneOffsetMinutes: manualOffsetMinutes,
      manualTimezoneName: manualName,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTimezoneModeKey, mode);
    if (manualOffsetMinutes != null) {
      await prefs.setInt(_kManualTimezoneOffsetMinutesKey, manualOffsetMinutes);
    }
    if (manualName != null) {
      await prefs.setString(_kManualTimezoneNameKey, manualName);
    }
  }

  Future<void> setSupabaseConfig(String url, String publishableKey) async {
    state = state.copyWith(
      supabaseUrl: url.trim(),
      supabasePublishableKey: publishableKey.trim(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSupabaseUrlKey, url.trim());
    await prefs.setString(_kSupabasePublishableKey, publishableKey.trim());
  }

  Future<void> clearSupabaseConfig() async {
    state = state.copyWith(
      supabaseUrl: '',
      supabasePublishableKey: '',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSupabaseUrlKey);
    await prefs.remove(_kSupabasePublishableKey);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, mode.name);
  }

  Future<void> setPalette(AppPaletteId palette) async {
    state = state.copyWith(paletteId: palette);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPaletteIdKey, palette.name);
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    state = state.copyWith(notificationsEnabled: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kNotificationsEnabledKey, enabled);
  }

  Future<void> setSuggestHabitsInFreeTime(bool enabled) async {
    state = state.copyWith(suggestHabitsInFreeTime: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSuggestHabitsInFreeTimeKey, enabled);
  }

  Future<void> setWeekStartsOnSunday(bool sunday) async {
    state = state.copyWith(weekStartsOnSunday: sunday);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kWeekStartsOnSundayKey, sunday);
  }

  Future<void> setCalendarViewMode(String mode) async {
    state = state.copyWith(calendarViewMode: mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCalendarViewKey, mode);
  }
}

final settingsNotifierProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  return SettingsNotifier();
});

