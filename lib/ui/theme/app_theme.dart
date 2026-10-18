// lib/ui/theme/app_theme.dart
//
// Dynamic app theme generator supporting Light/Dark modes and full aesthetic palettes
// (Neon Cyber, Pastel Dream, Nordic Frost, Warm Sunset, and Oceanic Classic).

import 'package:flutter/material.dart';
import 'package:kairos/ui/theme/theme_provider.dart';

class PaletteDefinition {
  final AppPaletteId id;
  final String name;
  final String description;
  final List<Color> previewColors;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color darkScaffold;
  final Color darkCard;
  final Color darkBorder;
  final Color lightScaffold;
  final Color lightCard;
  final Color lightBorder;

  const PaletteDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.previewColors,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.darkScaffold,
    required this.darkCard,
    required this.darkBorder,
    required this.lightScaffold,
    required this.lightCard,
    required this.lightBorder,
  });
}

class AppTheme {
  static const defaultPrimary = Color(0xFF3B82F6);

  static const Map<AppPaletteId, PaletteDefinition> palettes = {
    AppPaletteId.oceanic: PaletteDefinition(
      id: AppPaletteId.oceanic,
      name: 'Oceanic Classic',
      description: 'Clean sapphire blue, royal indigo, and crisp modern slate',
      previewColors: [Color(0xFF3B82F6), Color(0xFF6366F1), Color(0xFF10B981)],
      primary: Color(0xFF3B82F6),
      secondary: Color(0xFF6366F1),
      tertiary: Color(0xFF10B981),
      darkScaffold: Color(0xFF0F172A),
      darkCard: Color(0xFF1E293B),
      darkBorder: Color(0xFF334155),
      lightScaffold: Color(0xFFF8FAFC),
      lightCard: Colors.white,
      lightBorder: Color(0xFFE2E8F0),
    ),
    AppPaletteId.cyber: PaletteDefinition(
      id: AppPaletteId.cyber,
      name: 'Neon Cyber',
      description: 'Electric cyan, hot magenta, matrix lime on deep dark matrix',
      previewColors: [Color(0xFF00F5FF), Color(0xFFFF007F), Color(0xFF39FF14)],
      primary: Color(0xFF00F5FF),
      secondary: Color(0xFFFF007F),
      tertiary: Color(0xFF39FF14),
      darkScaffold: Color(0xFF080914),
      darkCard: Color(0xFF111427),
      darkBorder: Color(0xFF252D5A),
      lightScaffold: Color(0xFFF1F5F9),
      lightCard: Colors.white,
      lightBorder: Color(0xFFCBD5E1),
    ),
    AppPaletteId.pastel: PaletteDefinition(
      id: AppPaletteId.pastel,
      name: 'Pastel Dream',
      description: 'Soft lavender, blush rose, and mint sage with cozy tones',
      previewColors: [Color(0xFFC4B5FD), Color(0xFFF9A8D4), Color(0xFFA7F3D0)],
      primary: Color(0xFF9333EA),
      secondary: Color(0xFFDB2777),
      tertiary: Color(0xFF059669),
      darkScaffold: Color(0xFF161320),
      darkCard: Color(0xFF221E31),
      darkBorder: Color(0xFF3B3252),
      lightScaffold: Color(0xFFFAF7F5),
      lightCard: Colors.white,
      lightBorder: Color(0xFFE9D5FF),
    ),
    AppPaletteId.nordic: PaletteDefinition(
      id: AppPaletteId.nordic,
      name: 'Nordic Frost',
      description: 'Polar arctic ice, deep midnight ocean, and aurora green',
      previewColors: [Color(0xFF38BDF8), Color(0xFF818CF8), Color(0xFF34D399)],
      primary: Color(0xFF38BDF8),
      secondary: Color(0xFF818CF8),
      tertiary: Color(0xFF34D399),
      darkScaffold: Color(0xFF0B1120),
      darkCard: Color(0xFF151F33),
      darkBorder: Color(0xFF233556),
      lightScaffold: Color(0xFFF0F9FF),
      lightCard: Colors.white,
      lightBorder: Color(0xFFBAE6FD),
    ),
    AppPaletteId.sunset: PaletteDefinition(
      id: AppPaletteId.sunset,
      name: 'Warm Sunset',
      description: 'Vibrant tangerine, fiery rose, and golden dusk amber',
      previewColors: [Color(0xFFFB923C), Color(0xFFF43F5E), Color(0xFFFBBF24)],
      primary: Color(0xFFEA580C),
      secondary: Color(0xFFE11D48),
      tertiary: Color(0xFFD97706),
      darkScaffold: Color(0xFF181312),
      darkCard: Color(0xFF261D1A),
      darkBorder: Color(0xFF453029),
      lightScaffold: Color(0xFFFFFBEB),
      lightCard: Colors.white,
      lightBorder: Color(0xFFFED7AA),
    ),
  };

  static ThemeData buildTheme({
    required Brightness brightness,
    AppPaletteId paletteId = AppPaletteId.oceanic,
  }) {
    final isDark = brightness == Brightness.dark;
    final palette = palettes[paletteId] ?? palettes[AppPaletteId.oceanic]!;

    final scaffoldBg = isDark ? palette.darkScaffold : palette.lightScaffold;
    final cardBg = isDark ? palette.darkCard : palette.lightCard;
    final borderColor = isDark ? palette.darkBorder : palette.lightBorder;
    final primaryColor = isDark && paletteId == AppPaletteId.pastel 
        ? palette.previewColors[0] 
        : palette.primary;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: brightness,
      primary: primaryColor,
      secondary: palette.secondary,
      tertiary: palette.tertiary,
      surface: cardBg,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg,
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
        elevation: 0,
        centerTitle: false,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  /// Helper to convert hex strings like "#4A90D9" to Flutter Color.
  static Color colorFromHex(String hexString, [Color fallback = defaultPrimary]) {
    try {
      final buffer = StringBuffer();
      if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  static const List<String> presetColors = [
    '#3B82F6',
    '#10B981',
    '#F59E0B',
    '#EF4444',
    '#8B5CF6',
    '#EC4899',
    '#06B6D4',
    '#F97316',
    '#64748B',
  ];
}
