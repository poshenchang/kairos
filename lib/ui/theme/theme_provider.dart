// lib/ui/theme/theme_provider.dart
//
// Riverpod state providers for theme mode (Light/Dark/System) and full palette selection
// with automatic persistence to SharedPreferences.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppPaletteId {
  oceanic,
  cyber,
  pastel,
  nordic,
  sunset,
}

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('kairos_theme_mode');
    if (mode == 'light') {
      state = ThemeMode.light;
    } else if (mode == 'dark') {
      state = ThemeMode.dark;
    }
  }

  @override
  set state(ThemeMode value) {
    super.state = value;
    SharedPreferences.getInstance().then((p) => p.setString('kairos_theme_mode', value.name));
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemePaletteNotifier extends StateNotifier<AppPaletteId> {
  ThemePaletteNotifier() : super(AppPaletteId.oceanic) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString('kairos_palette_id');
    if (val != null) {
      final p = AppPaletteId.values.firstWhere(
        (e) => e.name == val,
        orElse: () => AppPaletteId.oceanic,
      );
      super.state = p;
    }
  }

  @override
  set state(AppPaletteId value) {
    super.state = value;
    SharedPreferences.getInstance().then((p) => p.setString('kairos_palette_id', value.name));
  }
}

final themePaletteProvider = StateNotifierProvider<ThemePaletteNotifier, AppPaletteId>((ref) {
  return ThemePaletteNotifier();
});
