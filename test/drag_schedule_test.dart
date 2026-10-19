// test/drag_schedule_test.dart
//
// Tests for drag-and-drop scheduling models, habit default schedules, and sidebar integration.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/services/habit_schedule_service.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/screens/calendar/widgets/drag_schedule_item.dart';
import 'package:kairos/ui/screens/calendar/widgets/schedule_sidebar.dart';

void main() {
  group('DragScheduleItem', () {
    test('habit scheduleSource format', () {
      final habit = Habit(
        id: 42,
        title: 'Morning Yoga',
        category: 'personal',
        targetFrequencyPerWeek: 3,
        minSessionMinutes: 60,
        maxSessionMinutes: 60,
        preferredWindow: 'morning',
        daysFilter: 'all',
        isActive: true,
        isDeleted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final item = DragScheduleItem(
        type: DragScheduleType.habit,
        title: habit.title,
        category: habit.category,
        durationMinutes: habit.minSessionMinutes,
        habit: habit,
      );

      expect(item.scheduleSource, equals('habit:42'));
      expect(item.durationMinutes, equals(60));
    });

    test('task scheduleSource format', () {
      final task = Task(
        id: 101,
        title: 'Complete Homework',
        category: 'schoolwork',
        priority: 3,
        dueDate: DateTime.now(),
        isCompleted: false,
        isRecurring: false,
        isDeleted: false,
        estimatedMinutes: 120,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final item = DragScheduleItem(
        type: DragScheduleType.task,
        title: task.title,
        category: task.category,
        durationMinutes: task.estimatedMinutes ?? 120,
        task: task,
      );

      expect(item.scheduleSource, equals('task:101'));
      expect(item.durationMinutes, equals(120));
    });

    test('subtask scheduleSource format', () {
      final task = Task(
        id: 101,
        title: 'Complete Homework',
        category: 'schoolwork',
        priority: 3,
        dueDate: DateTime.now(),
        isCompleted: false,
        isRecurring: false,
        isDeleted: false,
        estimatedMinutes: 120,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final subtask = Subtask(
        id: 7,
        taskId: 101,
        title: 'Problem Set 1',
        isCompleted: false,
        createdAt: DateTime.now(),
      );

      final item = DragScheduleItem(
        type: DragScheduleType.subtask,
        title: '${task.title}: ${subtask.title}',
        category: task.category,
        durationMinutes: 60,
        task: task,
        subtask: subtask,
      );

      expect(item.scheduleSource, equals('task:101:subtask:7'));
      expect(item.durationMinutes, equals(60));
    });

    test('prep scheduleSource format', () {
      final exam = Event(
        id: 55,
        title: 'Math Midterm',
        category: 'schoolwork',
        startTime: DateTime.now().add(const Duration(days: 3)),
        endTime: DateTime.now().add(const Duration(days: 3, hours: 2)),
        requiresPrep: true,
        prepMinutes: 120,
        isAutoScheduled: false,
        isRecurring: false,
        isDeleted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final item = DragScheduleItem(
        type: DragScheduleType.prep,
        title: 'Prep: ${exam.title}',
        category: exam.category,
        durationMinutes: 60,
        parentEvent: exam,
      );

      expect(item.scheduleSource, equals('event:55:prep'));
      expect(item.title, equals('Prep: Math Midterm'));
    });
  });

  group('HabitDefaultSlot Model', () {
    test('JSON serialization & deserialization', () {
      const slot = HabitDefaultSlot(
        weekday: 1, // Monday
        hour: 20,
        minute: 30,
        durationMinutes: 60,
      );

      final json = slot.toJson();
      expect(json['weekday'], equals(1));
      expect(json['hour'], equals(20));
      expect(json['minute'], equals(30));
      expect(json['durationMinutes'], equals(60));

      final restored = HabitDefaultSlot.fromJson(json);
      expect(restored.weekdayName, equals('Mon'));
      expect(restored.timeFormatted, equals('8:30 PM'));
      expect(restored.summary, equals('Mon at 8:30 PM (60m)'));
    });
  });

  group('ScheduleSidebar Widget', () {
    testWidgets('renders habits, preps, and tasks in sidebar with draggable items', (tester) async {
      final dummyTask = Task(
        id: 1,
        title: 'Write Essay',
        category: 'schoolwork',
        priority: 3,
        dueDate: DateTime.now().add(const Duration(days: 2)),
        isCompleted: false,
        isRecurring: false,
        isDeleted: false,
        estimatedMinutes: 120,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final dummyHabit = Habit(
        id: 10,
        title: 'Daily Reading',
        category: 'personal',
        targetFrequencyPerWeek: 5,
        minSessionMinutes: 60,
        maxSessionMinutes: 60,
        preferredWindow: 'evening',
        daysFilter: 'all',
        isActive: true,
        isDeleted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final dummyExam = Event(
        id: 77,
        title: 'Physics Final',
        category: 'schoolwork',
        startTime: DateTime.now().add(const Duration(days: 4)),
        endTime: DateTime.now().add(const Duration(days: 4, hours: 2)),
        requiresPrep: true,
        prepMinutes: 120,
        isAutoScheduled: false,
        isRecurring: false,
        isDeleted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            incompleteTasksStreamProvider.overrideWith((ref) => Stream.value([dummyTask])),
            activeHabitsProvider.overrideWith((ref) => Stream.value([dummyHabit])),
            weeklyHabitCompletionsProvider.overrideWith((ref) => Future.value({10: 2})),
            allEventsStreamProvider.overrideWith((ref) => Stream.value([dummyExam])),
            subtasksForTaskProvider.overrideWith((ref, taskId) => Stream.value([])),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 320,
                height: 750,
                child: ScheduleSidebar(
                  currentWeekStart: DateTime(2026, 10, 18),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Schedule Assistant'), findsOneWidget);
      expect(find.text('Daily Reading'), findsOneWidget);
      expect(find.text('Physics Final'), findsOneWidget);
      expect(find.text('Write Essay'), findsOneWidget);
      expect(find.text('Initialize Week with Default Habits'), findsOneWidget);

      // Verify Draggable widgets are present for habit, prep, and task
      expect(find.byType(Draggable<DragScheduleItem>), findsWidgets);
    });
  });
}
