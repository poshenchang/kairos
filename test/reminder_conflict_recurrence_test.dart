// test/reminder_conflict_recurrence_test.dart
//
// Unit tests for:
// 1. Event conflict detection & reminder exclusion in EventRepository
// 2. Recurring task completion rollover in TaskRepository
// 3. Form input default caching in FormDefaultsService

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/event_repository.dart';
import 'package:kairos/data/repositories/task_repository.dart';
import 'package:kairos/services/form_defaults_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late EventRepository eventRepo;
  late TaskRepository taskRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    eventRepo = EventRepository(db.eventDao, db.holidayDao);
    taskRepo = TaskRepository(db.taskDao);
  });

  tearDown(() async {
    await db.close();
  });

  group('Event Conflict Detection', () {
    test('detects overlapping event on same day and time', () async {
      // Insert an event 10:00 - 11:30
      final id = await db.eventDao.insertEvent(
        EventsCompanion.insert(
          title: 'Existing Lecture',
          category: Value('schoolwork'),
          eventType: Value('schoolwork'),
          startTime: DateTime(2026, 10, 20, 10, 0),
          endTime: DateTime(2026, 10, 20, 11, 30),
        ),
      );
      expect(id, isPositive);

      // Check conflict for overlapping slot (10:30 - 12:00)
      final conflicts = await eventRepo.getConflictingEvents(
        DateTime(2026, 10, 20, 10, 30),
        DateTime(2026, 10, 20, 12, 0),
      );

      expect(conflicts.length, 1);
      expect(conflicts.first.title, 'Existing Lecture');

      // Check that self (excludeEventId) does not conflict with self
      final selfConflicts = await eventRepo.getConflictingEvents(
        DateTime(2026, 10, 20, 10, 0),
        DateTime(2026, 10, 20, 11, 30),
        excludeEventId: id,
      );
      expect(selfConflicts, isEmpty);

      // Check that non-overlapping slot (11:30 - 12:30) does not conflict
      final nonOverlapping = await eventRepo.getConflictingEvents(
        DateTime(2026, 10, 20, 11, 30),
        DateTime(2026, 10, 20, 12, 30),
      );
      expect(nonOverlapping, isEmpty);
    });

    test('ignores reminders from triggering conflicts', () async {
      // Insert a reminder event
      await db.eventDao.insertEvent(
        EventsCompanion.insert(
          title: 'Quick Reminder',
          category: Value('personal'),
          eventType: Value('reminder'),
          startTime: DateTime(2026, 10, 20, 10, 0),
          endTime: DateTime(2026, 10, 20, 10, 0),
        ),
      );

      // Check conflict at 10:00 - reminders should be excluded
      final conflicts = await eventRepo.getConflictingEvents(
        DateTime(2026, 10, 20, 9, 30),
        DateTime(2026, 10, 20, 10, 30),
      );
      expect(conflicts, isEmpty);
    });
  });

  group('Recurring Task Completion Rollover', () {
    test('advances weekly recurring task dueDate and resets subtasks', () async {
      final initialDueDate = DateTime(2026, 10, 20, 14, 0);
      final taskId = await db.taskDao.insertTask(
        TasksCompanion.insert(
          title: 'Weekly Report',
          category: Value('work'),
          dueDate: initialDueDate,
          isRecurring: Value(true),
          rrule: Value('FREQ=WEEKLY'),
        ),
      );

      // Add subtasks
      await db.taskDao.insertSubtask(
        SubtasksCompanion.insert(
          taskId: taskId,
          title: 'Gather metrics',
          isCompleted: Value(true),
        ),
      );
      await db.taskDao.insertSubtask(
        SubtasksCompanion.insert(
          taskId: taskId,
          title: 'Write draft',
          isCompleted: Value(true),
        ),
      );

      // Complete the task instance
      await taskRepo.completeTask(taskId);

      final updatedTask = await db.taskDao.getTaskById(taskId);
      expect(updatedTask, isNotNull);
      // Should NOT be permanently completed
      expect(updatedTask!.isCompleted, isFalse);
      // Due date should be advanced by 7 days
      expect(updatedTask.dueDate, initialDueDate.add(const Duration(days: 7)));

      // Subtasks should be reset to not completed
      final subtasks = await db.taskDao.getSubtasksForTask(taskId);
      expect(subtasks.length, 2);
      expect(subtasks.every((s) => !s.isCompleted), isTrue);
    });

    test('decrements COUNT on recurring task and completes on last count', () async {
      final initialDueDate = DateTime(2026, 10, 20, 14, 0);
      final taskId = await db.taskDao.insertTask(
        TasksCompanion.insert(
          title: '2-Week Sprint Task',
          category: Value('work'),
          dueDate: initialDueDate,
          isRecurring: Value(true),
          rrule: Value('FREQ=WEEKLY;COUNT=2'),
        ),
      );

      // 1st completion: COUNT decrements to 1, dueDate advances
      await taskRepo.completeTask(taskId);
      var task = await db.taskDao.getTaskById(taskId);
      expect(task!.isCompleted, isFalse);
      expect(task.rrule, contains('COUNT=1'));
      expect(task.dueDate, initialDueDate.add(const Duration(days: 7)));

      // 2nd completion: Last count reached -> marked completed!
      await taskRepo.completeTask(taskId);
      task = await db.taskDao.getTaskById(taskId);
      expect(task!.isCompleted, isTrue);
    });
  });

  group('FormDefaultsService', () {
    test('persists and restores event form defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final service = FormDefaultsService.instance;
      await service.init();

      await service.saveEventDefaults(
        startDate: DateTime(2026, 10, 25),
        startTime: const TimeOfDay(hour: 14, minute: 30),
        endTime: const TimeOfDay(hour: 16, minute: 0),
        category: 'fitness',
      );

      expect(service.lastEventCategory, 'fitness');
      expect(service.lastEventStartTime?.hour, 14);
      expect(service.lastEventStartTime?.minute, 30);
      expect(service.lastEventEndTime?.hour, 16);
      expect(service.lastEventEndTime?.minute, 0);
      expect(service.lastEventStartDate?.day, 25);
    });

    test('persists and restores task and habit form defaults', () async {
      SharedPreferences.setMockInitialValues({});
      final service = FormDefaultsService.instance;
      await service.init();

      await service.saveTaskDefaults(
        dueDate: DateTime(2026, 10, 28),
        dueTime: const TimeOfDay(hour: 18, minute: 0),
        category: 'study',
        estimatedMinutes: 90,
      );

      expect(service.lastTaskCategory, 'study');
      expect(service.lastTaskEstimatedMinutes, 90);
      expect(service.lastTaskDueDate?.day, 28);
      expect(service.lastTaskDueTime?.hour, 18);

      await service.saveHabitDefaults(
        time: const TimeOfDay(hour: 7, minute: 0),
        category: 'health',
        durationMinutes: 45,
      );

      expect(service.lastHabitCategory, 'health');
      expect(service.lastHabitDuration, 45);
      expect(service.lastHabitTime?.hour, 7);
    });
  });

  group('Holiday Auto-Cancellation as Temporary Cancellation', () {
    test('autoCancelRecurringEventsForActiveHolidays adds EXDATE for holiday occurrences', () async {
      // 1. Insert a holiday on Friday Oct 23
      final holidayDate = DateTime(2026, 10, 23);
      await db.holidayDao.insertHoliday(
        HolidaysCompanion.insert(
          name: 'Mid-Autumn Festival',
          groupName: const Value('Taiwanese Holidays'),
          date: holidayDate,
          isEnabled: const Value(true),
        ),
      );

      // 2. Insert a weekly recurring event every Friday starting Oct 16
      final eventId = await db.eventDao.insertEvent(
        EventsCompanion.insert(
          title: 'Weekly Seminar',
          category: const Value('schoolwork'),
          eventType: const Value('lecture'),
          startTime: DateTime(2026, 10, 16, 14, 0),
          endTime: DateTime(2026, 10, 16, 16, 0),
          isRecurring: const Value(true),
          rrule: const Value('FREQ=WEEKLY;BYDAY=FR'),
        ),
      );

      // 3. Run autoCancelRecurringEventsForActiveHolidays
      final modified = await eventRepo.autoCancelRecurringEventsForActiveHolidays(
        rangeStart: DateTime(2026, 10, 1),
        rangeEnd: DateTime(2026, 11, 1),
      );
      expect(modified, equals(1));

      // 4. Verify EXDATE contains 2026-10-23
      final event = await db.eventDao.getEventById(eventId);
      expect(event!.rrule, contains('EXDATE=2026-10-23'));

      // 5. Expand events on the holiday week (Oct 18 - Oct 25)
      final weekEvents = await eventRepo.getExpandedEventsInRange(
        DateTime(2026, 10, 18),
        DateTime(2026, 10, 25),
      );
      // Oct 23 occurrence is hidden
      expect(weekEvents.where((e) => e.startTime.day == 23), isEmpty);

      // 6. Restore the occurrence (as done in All Events subpanel)
      await eventRepo.restoreRecurringOccurrence(eventId, '2026-10-23');
      final restoredEvent = await db.eventDao.getEventById(eventId);
      expect(EventRepository.getCancelledDates(restoredEvent!.rrule), isEmpty);

      // 7. Re-expand: Oct 23 occurrence reappears!
      final reExpanded = await eventRepo.getExpandedEventsInRange(
        DateTime(2026, 10, 18),
        DateTime(2026, 10, 25),
      );
      expect(reExpanded.where((e) => e.startTime.day == 23).length, equals(1));
    });

    test('getHolidaysForDate matches single-day and multi-day holiday breaks', () async {
      await db.holidayDao.insertHoliday(
        HolidaysCompanion.insert(
          name: 'Spring Break',
          groupName: const Value('Academic Breaks'),
          date: DateTime(2026, 3, 16),
          endDate: Value(DateTime(2026, 3, 20)),
          isEnabled: const Value(true),
        ),
      );

      // Match within break
      final inBreak = await db.holidayDao.getHolidaysForDate(DateTime(2026, 3, 18));
      expect(inBreak.length, equals(1));
      expect(inBreak.first.name, equals('Spring Break'));

      // No match outside break
      final outsideBreak = await db.holidayDao.getHolidaysForDate(DateTime(2026, 3, 25));
      expect(outsideBreak, isEmpty);
    });
  });
}
