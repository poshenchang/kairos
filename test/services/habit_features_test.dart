// test/services/habit_features_test.dart
//
// Tests for:
// 1. Auto-logging habit completions when time passes scheduled habit session.
// 2. TaskRepository dashboard tasks preserving advanced due date after recurring completion.
// 3. HabitScheduleNotifier.populateWeek removing existing habit instances before inserting default schedule.

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/task_repository.dart';
import 'package:kairos/services/habit_schedule_service.dart';
import 'package:kairos/services/habit_suggestion_service.dart';
import 'package:kairos/services/notification_service.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Habit Auto-Logging (Feature 4)', () {
    test('autoLogPassedHabits logs completed habit when event endTime is in the past', () async {
      // Create habit
      final habitId = await db.habitDao.insertHabit(
        HabitsCompanion.insert(
          title: 'Daily Reading',
          targetFrequencyPerWeek: const drift.Value(7),
          minSessionMinutes: const drift.Value(30),
        ),
      );

      final now = DateTime.now();
      // Insert a passed habit event
      final eventId = await db.eventDao.insertEvent(
        EventsCompanion.insert(
          title: 'Daily Reading',
          startTime: now.subtract(const Duration(hours: 2)),
          endTime: now.subtract(const Duration(hours: 1)),
          autoScheduleSource: drift.Value('habit:$habitId'),
          isAutoScheduled: const drift.Value(true),
        ),
      );

      // Verify no habit logs initially
      var logs = await db.habitDao.getLogsForHabit(habitId);
      expect(logs, isEmpty);

      // Run auto-logging
      final count = await HabitSuggestionService.instance.autoLogPassedHabits(db);
      expect(count, equals(1));

      // Verify habit log created with correct idempotent tag
      logs = await db.habitDao.getLogsForHabit(habitId);
      expect(logs.length, equals(1));
      expect(logs.first.notes, equals('auto_event:$eventId'));
      expect(logs.first.durationMinutes, equals(60));

      // Running again should be idempotent (0 newly logged)
      final secondCount = await HabitSuggestionService.instance.autoLogPassedHabits(db);
      expect(secondCount, equals(0));
      logs = await db.habitDao.getLogsForHabit(habitId);
      expect(logs.length, equals(1));
    });

    test('autoLogPassedHabits ignores events whose endTime is in the future', () async {
      final habitId = await db.habitDao.insertHabit(
        HabitsCompanion.insert(
          title: 'Podcast',
          targetFrequencyPerWeek: const drift.Value(7),
        ),
      );

      final now = DateTime.now();
      // Event ending in 30 minutes
      await db.eventDao.insertEvent(
        EventsCompanion.insert(
          title: 'Podcast',
          startTime: now.subtract(const Duration(minutes: 10)),
          endTime: now.add(const Duration(minutes: 30)),
          autoScheduleSource: drift.Value('habit:$habitId'),
          isAutoScheduled: const drift.Value(true),
        ),
      );

      final count = await HabitSuggestionService.instance.autoLogPassedHabits(db);
      expect(count, equals(0));
      final logs = await db.habitDao.getLogsForHabit(habitId);
      expect(logs, isEmpty);
    });
  });

  group('TaskRepository Recurring Due Date on Dashboard (Fix 3)', () {
    test('completed recurring task advances due date by 1 week on dashboard', () async {
      final repo = TaskRepository(db.taskDao);

      // Create a weekly recurring task due on Tuesday Oct 20 at 23:59
      final initialDue = DateTime(2026, 10, 20, 23, 59);
      final taskId = await db.taskDao.insertTask(
        TasksCompanion.insert(
          title: 'CS 101 Homework',
          dueDate: initialDue,
          estimatedMinutes: const drift.Value(120),
          isRecurring: const drift.Value(true),
          rrule: const drift.Value('FREQ=WEEKLY;BYDAY=TU'),
        ),
      );

      // Verify initial dashboard tasks
      var dashboardTasks = await repo.getDashboardTasks();
      expect(dashboardTasks.length, equals(1));
      expect(dashboardTasks.first.dueDate.day, equals(20));

      // Mark the task completed
      final completed = await repo.completeTask(taskId);
      expect(completed, isTrue);

      // Verify dashboard tasks now reflects the next occurrence 7 days later (Oct 27)
      dashboardTasks = await repo.getDashboardTasks();
      expect(dashboardTasks.length, equals(1));
      expect(dashboardTasks.first.dueDate.day, equals(27));
      expect(dashboardTasks.first.dueDate.isAfter(initialDue), isTrue);
    });
  });

  group('HabitScheduleService populateWeek (Fix 2)', () {
    test('populateWeek removes existing instances of the habit in the week before adding slots', () async {
      final notifier = HabitScheduleNotifier();
      final weekSunday = DateTime(2026, 10, 18); // Sunday

      // Create habit
      final habitId = await db.habitDao.insertHabit(
        HabitsCompanion.insert(
          title: 'Meditation',
          targetFrequencyPerWeek: const drift.Value(7),
        ),
      );
      final habit = (await db.habitDao.getHabitById(habitId))!;

      // Manually insert an old/custom habit event in that week (e.g. Monday at 07:00)
      final oldEventId = await db.eventDao.insertEvent(
        EventsCompanion.insert(
          title: 'Meditation',
          startTime: DateTime(2026, 10, 19, 7, 0),
          endTime: DateTime(2026, 10, 19, 7, 30),
          autoScheduleSource: drift.Value('habit:$habitId'),
          isAutoScheduled: const drift.Value(true),
        ),
      );

      // Set default template slots: Wednesday at 20:00 and Friday at 20:00
      await notifier.setSlots(habitId, const [
        HabitDefaultSlot(weekday: 3, hour: 20, minute: 0, durationMinutes: 45), // Wed
        HabitDefaultSlot(weekday: 5, hour: 20, minute: 0, durationMinutes: 45), // Fri
      ]);

      // Populate week
      final inserted = await notifier.populateWeek(
        weekSunday: weekSunday,
        habits: [habit],
        eventDao: db.eventDao,
      );

      expect(inserted, equals(2));

      // Verify old event was soft-deleted
      final oldEvent = await db.eventDao.getEventById(oldEventId);
      expect(oldEvent, isNotNull);
      expect(oldEvent!.isDeleted, isTrue);

      // Verify week now contains exactly the 2 template slots
      final weekEvents = await db.eventDao.getEventsInRange(
        weekSunday,
        weekSunday.add(const Duration(days: 7)),
      );
      final habitEvents = weekEvents.where((e) => e.autoScheduleSource == 'habit:$habitId').toList();
      expect(habitEvents.length, equals(2));
      expect(habitEvents.any((e) => e.startTime.weekday == 3 && e.startTime.hour == 20), isTrue);
      expect(habitEvents.any((e) => e.startTime.weekday == 5 && e.startTime.hour == 20), isTrue);
    });
  });

  group('Notification Defaults for Events (Feature 1)', () {
    test('standard event without explicit notify tag defaults to no reminder', () async {
      final notifService = NotificationService.instance;
      final normalEvent = Event(
        id: 101,
        title: 'Regular Meeting',
        category: 'work',
        eventType: 'event',
        startTime: DateTime.now().add(const Duration(hours: 2)),
        endTime: DateTime.now().add(const Duration(hours: 3)),
        isRecurring: false,
        isAutoScheduled: false,
        autoScheduleSource: null,
        isDeleted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        requiresPrep: false,
      );

      // Should complete cleanly without error
      await notifService.scheduleEventNotification(normalEvent);
    });

    test('derived event or reminder event can be scheduled with default offset 0', () async {
      final notifService = NotificationService.instance;
      final reminder = Event(
        id: 102,
        title: 'Drink Water',
        category: 'personal',
        eventType: 'reminder',
        startTime: DateTime.now().add(const Duration(hours: 2)),
        endTime: DateTime.now().add(const Duration(hours: 2)),
        isRecurring: false,
        isAutoScheduled: false,
        autoScheduleSource: null,
        isDeleted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        requiresPrep: false,
      );

      await notifService.scheduleEventNotification(reminder);

      final derivedHabit = Event(
        id: 103,
        title: 'Podcast Session',
        category: 'personal',
        eventType: 'event',
        startTime: DateTime.now().add(const Duration(hours: 3)),
        endTime: DateTime.now().add(const Duration(hours: 4)),
        isRecurring: false,
        isAutoScheduled: true,
        autoScheduleSource: 'habit:5',
        isDeleted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        requiresPrep: false,
      );

      await notifService.scheduleEventNotification(derivedHabit);
    });
  });

  group('Habit Suggestion in Free Time Settings (Feature 3)', () {
    test('does not suggest if feature is toggled off in settings', () async {
      const settings = SettingsState(
        notificationsEnabled: true,
        suggestHabitsInFreeTime: false,
      );
      final notifService = NotificationService.instance;

      final suggested = await HabitSuggestionService.instance.checkAndSuggestDailyHabit(
        db: db,
        settings: settings,
        notificationService: notifService,
      );
      expect(suggested, isFalse);
    });

    test('does not suggest if notifications are disabled in settings', () async {
      const settings = SettingsState(
        notificationsEnabled: false,
        suggestHabitsInFreeTime: true,
      );
      final notifService = NotificationService.instance;

      final suggested = await HabitSuggestionService.instance.checkAndSuggestDailyHabit(
        db: db,
        settings: settings,
        notificationService: notifService,
      );
      expect(suggested, isFalse);
    });
  });

  group('SmartSuggestion Ongoing Event Detection (Dashboard Hero Card)', () {
    test('detects when user is currently attending an event and returns In Event', () async {
      final now = DateTime.now();

      // Insert an ongoing event right now
      await db.eventDao.insertEvent(
        EventsCompanion.insert(
          title: 'Physics Lecture',
          startTime: now.subtract(const Duration(minutes: 20)),
          endTime: now.add(const Duration(minutes: 40)),
          category: const drift.Value('schoolwork'),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      // Await today's events
      await container.read(todayEventsProvider.future);
      final suggestion = container.read(smartSuggestionProvider);

      expect(suggestion.hasFreeTime, isFalse);
      expect(suggestion.title, contains('Physics Lecture'));
      expect(suggestion.title, startsWith('In Event:'));
      expect(suggestion.description, contains('remaining'));
    });
  });

  group('Habit Completions for Specific Week (Sidebar Navigation)', () {
    test('returns completions for the logged week and empty for future week', () async {
      final habitId = await db.habitDao.insertHabit(
        HabitsCompanion.insert(
          title: 'Running',
          targetFrequencyPerWeek: const drift.Value(3),
        ),
      );

      final currentSunday = DateTime(2026, 10, 18);
      final futureSunday = DateTime(2026, 10, 25);

      // Log completion on Monday Oct 19
      await db.habitDao.logHabitCompletion(
        HabitLogsCompanion.insert(
          habitId: habitId,
          completedAt: DateTime.utc(2026, 10, 19, 10, 0),
          durationMinutes: const drift.Value(45),
        ),
      );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      final currentWeekCompletions = await container.read(habitCompletionsForWeekProvider(currentSunday).future);
      expect(currentWeekCompletions[habitId], equals(1));

      final futureWeekCompletions = await container.read(habitCompletionsForWeekProvider(futureSunday).future);
      expect(futureWeekCompletions[habitId] ?? 0, equals(0));
    });
  });
}


