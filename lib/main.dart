// lib/main.dart
//
// Kairos: Student Smart Calendar, Habit Tracker, and Auto-Scheduler.

import 'dart:async';
import 'dart:ui';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/core/scheduler/scheduler_provider.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/services/habit_suggestion_service.dart';
import 'package:kairos/services/notification_service.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/router.dart';
import 'package:kairos/ui/theme/app_theme.dart';
import 'package:kairos/ui/theme/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.instance.initialize();
  runApp(const ProviderScope(child: KairosApp()));
}

class KairosApp extends ConsumerStatefulWidget {
  const KairosApp({super.key});

  @override
  ConsumerState<KairosApp> createState() => _KairosAppState();
}

class _KairosAppState extends ConsumerState<KairosApp> {
  Timer? _suggestionTimer;

  @override
  void initState() {
    super.initState();
    _bootstrapData();
    _startHabitMonitoring();
  }

  @override
  void dispose() {
    _suggestionTimer?.cancel();
    super.dispose();
  }

  void _startHabitMonitoring() {
    // Run initial checks 2 seconds after startup
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _runHabitChecks();
    });

    // Run periodic checks every 15 minutes
    _suggestionTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (mounted) _runHabitChecks();
    });
  }

  Future<void> _runHabitChecks() async {
    final db = ref.read(appDatabaseProvider);
    final settings = ref.read(settingsNotifierProvider);
    final notificationService = ref.read(notificationServiceProvider);
    await HabitSuggestionService.instance.runPeriodicChecks(
      db: db,
      settings: settings,
      notificationService: notificationService,
      onHabitsUpdated: () {
        ref.invalidate(weeklyHabitCompletionsProvider);
      },
    );
  }

  Future<void> _bootstrapData() async {
    final db = ref.read(appDatabaseProvider);

    // Seed default system categories if empty
    final existingCats = await db.categoryDao.getAllCategories();
    if (existingCats.isEmpty) {
      final defaults = [
        CategoriesCompanion.insert(
          name: 'Schoolwork',
          slug: 'schoolwork',
          emoji: const Value('🎓'),
          colorHex: const Value('#4A90D9'),
          isSystem: const Value(true),
        ),
        CategoriesCompanion.insert(
          name: 'Work',
          slug: 'work',
          emoji: const Value('💼'),
          colorHex: const Value('#E67E22'),
          isSystem: const Value(true),
        ),
        CategoriesCompanion.insert(
          name: 'Research',
          slug: 'research',
          emoji: const Value('🔬'),
          colorHex: const Value('#8E44AD'),
          isSystem: const Value(true),
        ),
        CategoriesCompanion.insert(
          name: 'Personal',
          slug: 'personal',
          emoji: const Value('🧘'),
          colorHex: const Value('#27AE60'),
          isSystem: const Value(true),
        ),
        CategoriesCompanion.insert(
          name: 'Social',
          slug: 'social',
          emoji: const Value('🎉'),
          colorHex: const Value('#EC4899'),
          isSystem: const Value(true),
        ),
        CategoriesCompanion.insert(
          name: 'Commute',
          slug: 'transportation',
          emoji: const Value('🚆'),
          colorHex: const Value('#E74C3C'),
          isSystem: const Value(true),
        ),
        CategoriesCompanion.insert(
          name: 'Other',
          slug: 'other',
          emoji: const Value('🌐'),
          colorHex: const Value('#7F8C8D'),
          isSystem: const Value(true),
        ),
      ];
      for (final cat in defaults) {
        await db.categoryDao.insertCategory(cat);
      }
    } else {
      // Ensure Social category exists for existing databases
      final hasSocial = existingCats.any((c) => c.slug == 'social');
      if (!hasSocial) {
        await db.categoryDao.insertCategory(
          CategoriesCompanion.insert(
            name: 'Social',
            slug: 'social',
            emoji: const Value('🎉'),
            colorHex: const Value('#EC4899'),
            isSystem: const Value(true),
          ),
        );
      }
    }

    // Seed default holidays if empty
    await db.holidayDao.seedDefaultHolidays(DateTime.now().year);
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(themeModeProvider);
    final paletteId = ref.watch(themePaletteProvider);

    return MaterialApp.router(
      title: 'Kairos',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      theme: AppTheme.buildTheme(brightness: Brightness.light, paletteId: paletteId),
      darkTheme: AppTheme.buildTheme(brightness: Brightness.dark, paletteId: paletteId),
      themeMode: mode,
      routerConfig: appRouter,
    );
  }
}
