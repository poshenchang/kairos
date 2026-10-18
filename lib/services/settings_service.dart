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

class SettingsState {
  final ThemeMode themeMode;
  final AppPaletteId paletteId;
  final bool notificationsEnabled;
  final bool weekStartsOnSunday;
  final String calendarViewMode; // 'timetable' or 'list'

  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.paletteId = AppPaletteId.oceanic,
    this.notificationsEnabled = true,
    this.weekStartsOnSunday = true,
    this.calendarViewMode = 'timetable', // Timetable is default as requested!
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    AppPaletteId? paletteId,
    bool? notificationsEnabled,
    bool? weekStartsOnSunday,
    String? calendarViewMode,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      paletteId: paletteId ?? this.paletteId,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      weekStartsOnSunday: weekStartsOnSunday ?? this.weekStartsOnSunday,
      calendarViewMode: calendarViewMode ?? this.calendarViewMode,
    );
  }
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
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

    state = SettingsState(
      themeMode: themeMode,
      paletteId: palette,
      notificationsEnabled: notifs,
      weekStartsOnSunday: sunday,
      calendarViewMode: viewMode,
    );
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

