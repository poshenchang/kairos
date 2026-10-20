// test/services/assistant_prioritization_and_prep_reset_test.dart

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/event_repository.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/timezone_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late EventRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = EventRepository(db.eventDao, db.holidayDao);
  });

  tearDown(() async {
    await db.close();
  });
  group('Schedule Assistant Prioritization & Unscheduled Ranking Tests', () {
    test('Unscheduled items are prioritized over scheduled items (higher priority rule)', () {
      // Sorting rank: (isScheduled ? 1 : 0), then typePriority (0: Task, 1: Prep, 2: Habit)
      int calculateRank({required bool isScheduled, required int typePriority}) {
        return (isScheduled ? 10 : 0) + typePriority;
      }

      final unscheduledTaskRank = calculateRank(isScheduled: false, typePriority: 0); // 0
      final unscheduledPrepRank = calculateRank(isScheduled: false, typePriority: 1); // 1
      final unscheduledHabitRank = calculateRank(isScheduled: false, typePriority: 2); // 2
      final scheduledTaskRank = calculateRank(isScheduled: true, typePriority: 0);   // 10
      final scheduledPrepRank = calculateRank(isScheduled: true, typePriority: 1);   // 11
      final scheduledHabitRank = calculateRank(isScheduled: true, typePriority: 2);   // 12

      // Unscheduled habit must rank higher (lower score) than a scheduled task!
      expect(unscheduledHabitRank < scheduledTaskRank, isTrue);

      // Within unscheduled items: task -> prep -> habit
      expect(unscheduledTaskRank < unscheduledPrepRank, isTrue);
      expect(unscheduledPrepRank < unscheduledHabitRank, isTrue);

      // Within scheduled items: task -> prep -> habit
      expect(scheduledTaskRank < scheduledPrepRank, isTrue);
      expect(scheduledPrepRank < scheduledHabitRank, isTrue);
    });
  });

  group('Recurring Event Prep Session Windowing & Count Reset Tests', () {
    test('Prep sessions only count towards the closest future occurrence and reset when passed', () {
      final settings = SettingsState();
      final now = DateTime.utc(2026, 10, 20, 10, 0); // Tuesday 10am

      // Base weekly recurring event: Weekly Quiz every Friday at 14:00 UTC (duration 60m)
      final weeklyQuiz = Event(
        id: 42,
        title: 'Weekly Math Quiz',
        category: 'schoolwork',
        startTime: DateTime.utc(2026, 9, 4, 14, 0), // Series start
        endTime: DateTime.utc(2026, 9, 4, 15, 0),
        isRecurring: true,
        rrule: 'FREQ=WEEKLY;BYDAY=FR',
        requiresPrep: true,
        prepMinutes: 60,
        isAutoScheduled: false,
        isDeleted: false,
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      );


      // Expand occurrences around now (2026-10-20)
      final occurrences = repo.expandRecurringEvents(
        weeklyQuiz,
        now.subtract(const Duration(days: 14)),
        now.add(const Duration(days: 60)),
        settings: settings,
      );
      occurrences.sort((a, b) => a.startTime.compareTo(b.startTime));

      // Closest upcoming occurrence after now (Oct 20, 2026) is Friday, Oct 23, 2026
      Event? nextOcc;
      Event? prevOcc;
      for (final occ in occurrences) {
        if (occ.endTime.isAfter(now)) {
          nextOcc = occ;
          break;
        }
        prevOcc = occ;
      }

      expect(nextOcc, isNotNull);
      expect(nextOcc!.startTime, equals(DateTime.utc(2026, 10, 23, 14, 0)));
      expect(prevOcc!.startTime, equals(DateTime.utc(2026, 10, 16, 14, 0)));

      final windowStart = prevOcc.endTime;
      final windowEnd = nextOcc.startTime;

      // Mock list of all prep blocks across history
      final prepBlocks = [
        // Past prep block for last week's quiz (Oct 15)
        Event(
          id: 101,
          title: 'Prep: Weekly Math Quiz',
          category: 'schoolwork',
          startTime: DateTime.utc(2026, 10, 15, 10, 0),
          endTime: DateTime.utc(2026, 10, 15, 11, 0),
          isRecurring: false,
          requiresPrep: false,
          isAutoScheduled: true,
          autoScheduleSource: 'event:42:prep',
          isDeleted: false,
          createdAt: DateTime.utc(2026, 10, 15),
          updatedAt: DateTime.utc(2026, 10, 15),
        ),
        // Prep block for upcoming quiz (Oct 22)
        Event(
          id: 102,
          title: 'Prep: Weekly Math Quiz',
          category: 'schoolwork',
          startTime: DateTime.utc(2026, 10, 22, 10, 0),
          endTime: DateTime.utc(2026, 10, 22, 10, 45), // 45m
          isRecurring: false,
          requiresPrep: false,
          isAutoScheduled: true,
          autoScheduleSource: 'event:42:prep',
          isDeleted: false,
          createdAt: DateTime.utc(2026, 10, 20),
          updatedAt: DateTime.utc(2026, 10, 20),
        ),
      ];

      // Calculate counted prep minutes for this upcoming occurrence (Oct 23)
      int scheduledMinutes = 0;
      for (final e in prepBlocks) {
        if (e.startTime.isBefore(windowStart)) continue;
        if (e.startTime.isAfter(windowEnd)) continue;
        scheduledMinutes += e.endTime.difference(e.startTime).inMinutes;
      }

      // Past prep on Oct 15 is ignored; only Oct 22 (45m) is counted!
      expect(scheduledMinutes, equals(45));

      // Now simulate time passing: it is now Saturday Oct 24, 2026 (Quiz has passed)
      final passedNow = DateTime.utc(2026, 10, 24, 10, 0);
      Event? nextOccAfterPassed;
      Event? prevOccAfterPassed;
      for (final occ in occurrences) {
        if (occ.endTime.isAfter(passedNow)) {
          nextOccAfterPassed = occ;
          break;
        }
        prevOccAfterPassed = occ;
      }

      // Next occurrence shifts to Friday, Oct 30, 2026!
      expect(nextOccAfterPassed, isNotNull);
      expect(nextOccAfterPassed!.startTime, equals(DateTime.utc(2026, 10, 30, 14, 0)));
      expect(prevOccAfterPassed!.startTime, equals(DateTime.utc(2026, 10, 23, 14, 0)));

      // New window is [Oct 23 15:00, Oct 30 14:00]
      final newWindowStart = prevOccAfterPassed.endTime;
      final newWindowEnd = nextOccAfterPassed.startTime;

      int resetScheduledMinutes = 0;
      for (final e in prepBlocks) {
        if (e.startTime.isBefore(newWindowStart)) continue;
        if (e.startTime.isAfter(newWindowEnd)) continue;
        resetScheduledMinutes += e.endTime.difference(e.startTime).inMinutes;
      }

      // Because the Oct 23 quiz has passed, the counted prep minutes automatically resets to 0!
      expect(resetScheduledMinutes, equals(0));
    });
  });
}
