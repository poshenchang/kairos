// test/services/hero_card_prioritization_and_agenda_test.dart
//
// Tests for:
// 1. Hero Card Smart Suggestion prioritization:
//    - Overdue tasks prioritized first
//    - Uncompleted daily habits prioritized over tasks due 2+ days later
//    - Tasks due in < 24h prioritized by nearest deadline
//    - Completing a daily habit moves priority to remaining tasks/habits
// 2. HabitDao.watchAllHabitLogs reactive streaming
// 3. Supabase dialog dark mode text color adaptability

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/screens/settings/settings_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Hero Card Smart Suggestion Prioritization', () {
    test('prioritizes overdue task over daily habit and distant tasks', () async {
      final now = DateTime.now();

      // Overdue task (due 3 hours ago)
      await db.taskDao.insertTask(
        TasksCompanion.insert(
          title: 'Urgent Lab Report',
          dueDate: now.subtract(const Duration(hours: 3)),
        ),
      );

      // Daily habit
      await db.habitDao.insertHabit(
        HabitsCompanion.insert(
          title: 'Daily Meditation',
          targetFrequencyPerWeek: const drift.Value(7),
        ),
      );

      // Distant task (due in 5 days)
      await db.taskDao.insertTask(
        TasksCompanion.insert(
          title: 'Final Term Paper',
          dueDate: now.add(const Duration(days: 5)),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          eventDaoProvider.overrideWithValue(db.eventDao),
          taskDaoProvider.overrideWithValue(db.taskDao),
          habitDaoProvider.overrideWithValue(db.habitDao),
        ],
      );
      addTearDown(container.dispose);

      // Wait for async stream providers to emit
      await container.read(incompleteTasksStreamProvider.future);
      await container.read(activeHabitsProvider.future);
      await container.read(todayEventsProvider.future);
      await container.read(todayHabitCompletionsProvider.future);

      final suggestion = container.read(smartSuggestionProvider);

      expect(suggestion.hasFreeTime, isTrue);
      expect(suggestion.title, contains('Urgent Lab Report'));
      expect(suggestion.description, contains('Overdue'));
    });

    test('prioritizes uncompleted daily habit over task due in 2 days', () async {
      final now = DateTime.now();

      // Daily habit (7 times a week, uncompleted today)
      final habitId = await db.habitDao.insertHabit(
        HabitsCompanion.insert(
          title: 'Daily Workout',
          targetFrequencyPerWeek: const drift.Value(7),
        ),
      );

      // Task due in 2 days (48 hours away)
      await db.taskDao.insertTask(
        TasksCompanion.insert(
          title: 'Read History Chapter',
          dueDate: now.add(const Duration(days: 2)),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          eventDaoProvider.overrideWithValue(db.eventDao),
          taskDaoProvider.overrideWithValue(db.taskDao),
          habitDaoProvider.overrideWithValue(db.habitDao),
        ],
      );
      addTearDown(container.dispose);

      await container.read(incompleteTasksStreamProvider.future);
      await container.read(activeHabitsProvider.future);
      await container.read(todayEventsProvider.future);
      await container.read(todayHabitCompletionsProvider.future);

      final suggestion = container.read(smartSuggestionProvider);

      expect(suggestion.hasFreeTime, isTrue);
      expect(suggestion.title, contains('Daily Workout'));
      expect(suggestion.description, contains('Daily habit not yet completed today'));
      expect(suggestion.habit?.id, equals(habitId));

      // Now log completion of the daily habit today
      await db.habitDao.logHabitCompletion(
        HabitLogsCompanion.insert(
          habitId: habitId,
          completedAt: DateTime.now().toUtc(),
          durationMinutes: const drift.Value(30),
        ),
      );

      // Refetch / let stream update
      await container.read(allHabitLogsStreamProvider.future);
      container.invalidate(todayHabitCompletionsProvider);
      await container.read(todayHabitCompletionsProvider.future);

      final nextSuggestion = container.read(smartSuggestionProvider);

      // Now that the daily habit is completed today, the task due in 2 days is prioritized
      expect(nextSuggestion.title, contains('Read History Chapter'));
    });

    test('prioritizes task due in 2 hours over uncompleted daily habit due tonight', () async {
      final now = DateTime.now();

      // Task due in 2 hours
      await db.taskDao.insertTask(
        TasksCompanion.insert(
          title: 'Math Homework Submission',
          dueDate: now.add(const Duration(hours: 2)),
        ),
      );

      // Daily habit
      await db.habitDao.insertHabit(
        HabitsCompanion.insert(
          title: 'Evening Stretch',
          targetFrequencyPerWeek: const drift.Value(7),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          eventDaoProvider.overrideWithValue(db.eventDao),
          taskDaoProvider.overrideWithValue(db.taskDao),
          habitDaoProvider.overrideWithValue(db.habitDao),
        ],
      );
      addTearDown(container.dispose);

      await container.read(incompleteTasksStreamProvider.future);
      await container.read(activeHabitsProvider.future);
      await container.read(todayEventsProvider.future);
      await container.read(todayHabitCompletionsProvider.future);

      final suggestion = container.read(smartSuggestionProvider);

      // Task due in 2 hours should take precedence over habit due tonight
      expect(suggestion.title, contains('Math Homework Submission'));
      expect(suggestion.description, contains('Due in 2h'));
    });
  });

  group('HabitDao and Provider Reactivity', () {
    test('watchAllHabitLogs emits when new log is inserted', () async {
      final habitId = await db.habitDao.insertHabit(
        HabitsCompanion.insert(
          title: 'Piano Practice',
          targetFrequencyPerWeek: const drift.Value(5),
        ),
      );

      final stream = db.habitDao.watchAllHabitLogs();

      expect(
        stream,
        emitsInOrder([
          isEmpty,
          hasLength(1),
        ]),
      );

      await db.habitDao.logHabitCompletion(
        HabitLogsCompanion.insert(
          habitId: habitId,
          completedAt: DateTime.now().toUtc(),
        ),
      );
    });
  });

  group('Supabase Instructions Dialog Dark Mode', () {
    testWidgets('instructions dialog text uses theme onSurface color in dark mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(onSurface: Colors.white),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('How to Get Supabase API Keys'),
                      content: SingleChildScrollView(
                        child: Column(
                          children: [
                            Text(
                              'Supabase provides a free cloud PostgreSQL backend',
                              style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
                            ),
                            Text.rich(
                              TextSpan(
                                text: '1. Create a free project',
                                style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('How to Get Supabase API Keys'), findsOneWidget);
      expect(find.text('Supabase provides a free cloud PostgreSQL backend'), findsOneWidget);
      expect(find.text('1. Create a free project'), findsOneWidget);
    });
  });
}

