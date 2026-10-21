// lib/ui/providers/app_providers.dart
//
// Application-level state providers for categories, events, tasks, habits,
// and smart dashboard suggestions.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/data/repositories/repository_providers.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/timezone_service.dart';

// ── Categories ──────────────────────────────────────────────────────────────

final allCategoriesProvider = StreamProvider<List<Category>>((ref) {
  final dao = ref.watch(categoryDaoProvider);
  return dao.watchAllCategories();
});

// ── Events ──────────────────────────────────────────────────────────────────

final allEventsStreamProvider = StreamProvider<List<Event>>((ref) {
  final dao = ref.watch(eventDaoProvider);
  return dao.watchAllEvents();
});

final todayEventsProvider = FutureProvider<List<Event>>((ref) async {
  final repo = ref.watch(eventRepositoryProvider);
  final settings = ref.read(settingsNotifierProvider);
  final now = TimezoneService.instance.activeNow(settings);
  final startWall = DateTime(now.year, now.month, now.day);
  final endWall = startWall.add(const Duration(days: 1));
  final startUtc = TimezoneService.instance.fromActiveTime(startWall, settings);
  final endUtc = TimezoneService.instance.fromActiveTime(endWall, settings);
  return repo.getExpandedEventsInRange(startUtc, endUtc, settings);
});

final selectedDateProvider = StateProvider<DateTime>((ref) => DateTime.now());

final selectedDateEventsProvider = FutureProvider<List<Event>>((ref) async {
  final date = ref.watch(selectedDateProvider);
  final repo = ref.watch(eventRepositoryProvider);
  final settings = ref.read(settingsNotifierProvider);
  final startWall = DateTime(date.year, date.month, date.day);
  final endWall = startWall.add(const Duration(days: 1));
  final startUtc = TimezoneService.instance.fromActiveTime(startWall, settings);
  final endUtc = TimezoneService.instance.fromActiveTime(endWall, settings);
  return repo.getExpandedEventsInRange(startUtc, endUtc, settings);
});

final weekEventsProvider = FutureProvider.family<List<Event>, DateTime>((ref, weekStart) async {
  final repo = ref.watch(eventRepositoryProvider);
  final settings = ref.read(settingsNotifierProvider);
  final startWall = DateTime(weekStart.year, weekStart.month, weekStart.day);
  final endWall = startWall.add(const Duration(days: 7));
  final startUtc = TimezoneService.instance.fromActiveTime(startWall, settings);
  final endUtc = TimezoneService.instance.fromActiveTime(endWall, settings);
  return repo.getExpandedEventsInRange(startUtc, endUtc, settings);
});

final holidaysForDateProvider = FutureProvider.family<List<Holiday>, DateTime>((ref, date) async {
  final dao = ref.watch(holidayDaoProvider);
  return dao.getHolidaysForDate(date);
});

// ── Tasks ───────────────────────────────────────────────────────────────────

final incompleteTasksStreamProvider = StreamProvider<List<Task>>((ref) {
  final dao = ref.watch(taskDaoProvider);
  return dao.watchIncompleteTasks();
});

/// Returns incomplete tasks with recurring tasks collapsed to only their next occurrence.
final dashboardTasksProvider = FutureProvider<List<Task>>((ref) async {
  // Re-run when the raw tasks stream emits
  ref.watch(incompleteTasksStreamProvider);
  final repo = ref.watch(taskRepositoryProvider);
  return repo.getDashboardTasks();
});

final subtasksForTaskProvider = StreamProvider.family<List<Subtask>, int>((ref, taskId) {
  final dao = ref.watch(taskDaoProvider);
  return dao.watchSubtasksForTask(taskId);
});

// ── Habits ──────────────────────────────────────────────────────────────────

final allHabitLogsStreamProvider = StreamProvider<List<HabitLog>>((ref) {
  final dao = ref.watch(habitDaoProvider);
  return dao.watchAllHabitLogs();
});

final activeHabitsProvider = StreamProvider<List<Habit>>((ref) {
  final dao = ref.watch(habitDaoProvider);
  return dao.watchActiveHabits();
});

final allHabitsProvider = StreamProvider<List<Habit>>((ref) {
  final dao = ref.watch(habitDaoProvider);
  return dao.watchAllHabits();
});

final habitCompletionsForWeekProvider = StreamProvider.family<Map<int, int>, DateTime>((ref, weekSunday) {
  final dao = ref.watch(habitDaoProvider);
  final start = DateTime(weekSunday.year, weekSunday.month, weekSunday.day);
  final end = start.add(const Duration(days: 7));
  return dao.watchWeeklyCompletions(start, end);
});

final weeklyHabitCompletionsProvider = StreamProvider<Map<int, int>>((ref) {
  final dao = ref.watch(habitDaoProvider);
  final settings = ref.watch(settingsNotifierProvider);
  final now = TimezoneService.instance.activeNow(settings);
  final daysBack = now.weekday % 7; // Sunday start (Sunday = weekday 7 % 7 = 0)
  final sunday = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysBack));
  final startWall = DateTime(sunday.year, sunday.month, sunday.day);
  final endWall = startWall.add(const Duration(days: 7));
  final start = TimezoneService.instance.fromActiveTime(startWall, settings);
  final end = TimezoneService.instance.fromActiveTime(endWall, settings);
  return dao.watchWeeklyCompletions(start, end);
});

final todayHabitCompletionsProvider = StreamProvider<Map<int, int>>((ref) {
  final dao = ref.watch(habitDaoProvider);
  final settings = ref.watch(settingsNotifierProvider);
  final now = TimezoneService.instance.activeNow(settings);
  final startWall = DateTime(now.year, now.month, now.day);
  final endWall = startWall.add(const Duration(days: 1));
  final start = TimezoneService.instance.fromActiveTime(startWall, settings);
  final end = TimezoneService.instance.fromActiveTime(endWall, settings);
  return dao.watchWeeklyCompletions(start, end);
});

// ── Smart Free Time & Suggestion ─────────────────────────────────────────────

enum SmartSuggestionPeriod {
  night,   // 22:00 - 04:00 (Rewind & Wind Down)
  morning, // 04:00 - 09:00 (Get Ready for the Day)
  daytime, // 09:00 - 22:00 (What to Do Next)
}

class HeroQuote {
  final String text;
  final String author;

  const HeroQuote(this.text, this.author);

  static const List<HeroQuote> morningQuotes = [
    HeroQuote('The secret of getting ahead is getting started.', 'Mark Twain'),
    HeroQuote('Each morning we are born again. What we do today matters most.', 'Buddha'),
    HeroQuote('Small daily improvements over time lead to stunning results.', 'Robin Sharma'),
    HeroQuote('Focus on being productive instead of busy.', 'Tim Ferriss'),
    HeroQuote('Action is the foundational key to all success.', 'Pablo Picasso'),
    HeroQuote('Make each day your masterpiece.', 'John Wooden'),
    HeroQuote('Either you run the day, or the day runs you.', 'Jim Rohn'),
    HeroQuote('Start where you are. Use what you have. Do what you can.', 'Arthur Ashe'),
    HeroQuote('Your time is limited, don\'t waste it living someone else\'s life.', 'Steve Jobs'),
    HeroQuote('Today\'s accomplishments were yesterday\'s impossibilities.', 'Robert H. Schuller'),
    HeroQuote('Consistency is the DNA of mastery.', 'Robin Sharma'),
  ];

  static const List<HeroQuote> eveningQuotes = [
    HeroQuote('Sleep is the best meditation.', 'Dalai Lama'),
    HeroQuote('Tomorrow is a fresh start with no mistakes in it yet.', 'L.M. Montgomery'),
    HeroQuote('Take rest; a field that has rested gives a bountiful crop.', 'Ovid'),
    HeroQuote('Rest is not idleness, but the key to sustained productivity.', 'Alex Soojung-Kim Pang'),
    HeroQuote('Each night, when I go to sleep, I die. And the next morning, when I wake up, I am reborn.', 'Mahatma Gandhi'),
    HeroQuote('Finish each day and be done with it. You have done what you could.', 'Ralph Waldo Emerson'),
    HeroQuote('End the day with gratitude. There is always something to be thankful for.', 'Unknown'),
  ];

  static HeroQuote getMorningQuote(DateTime date) {
    final index = (date.year + date.month + date.day) % morningQuotes.length;
    return morningQuotes[index];
  }

  static HeroQuote getEveningQuote(DateTime date) {
    final index = (date.year + date.month + date.day) % eveningQuotes.length;
    return eveningQuotes[index];
  }
}

class SmartSuggestion {
  final Duration freeDuration;
  final String title;
  final String description;
  final String actionLabel;
  final String category;
  final bool hasFreeTime;
  final Task? task;
  final Habit? habit;
  final SmartSuggestionPeriod period;
  final String? quote;
  final String? quoteAuthor;
  final String? badgeLabel;

  const SmartSuggestion({
    required this.freeDuration,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.category,
    required this.hasFreeTime,
    this.task,
    this.habit,
    this.period = SmartSuggestionPeriod.daytime,
    this.quote,
    this.quoteAuthor,
    this.badgeLabel,
  });
}

final smartSuggestionProvider = Provider<SmartSuggestion>((ref) {
  final todayEventsAsync = ref.watch(todayEventsProvider);
  final tasksAsync = ref.watch(incompleteTasksStreamProvider);
  final habitsAsync = ref.watch(activeHabitsProvider);
  final habitCountsAsync = ref.watch(weeklyHabitCompletionsProvider);
  final todayHabitCountsAsync = ref.watch(todayHabitCompletionsProvider);

  final settings = ref.watch(settingsNotifierProvider);
  final now = TimezoneService.instance.activeNow(settings);
  final todayEvents = todayEventsAsync.value ?? [];
  final tasks = tasksAsync.value ?? [];
  final habits = habitsAsync.value ?? [];
  final habitCounts = habitCountsAsync.value ?? {};
  final todayHabitCounts = todayHabitCountsAsync.value ?? {};

  // Time-of-day periods:
  // Night / Rewind: 10:00 PM to 04:00 AM (22:00 - 03:59)
  // Morning Kickoff: 04:00 AM to 09:00 AM (04:00 - 08:59)
  // Daytime: 09:00 AM to 10:00 PM (09:00 - 21:59)
  final isNight = now.hour >= 22 || now.hour < 4;
  final isMorning = now.hour >= 4 && now.hour < 9;
  final period = isNight
      ? SmartSuggestionPeriod.night
      : (isMorning ? SmartSuggestionPeriod.morning : SmartSuggestionPeriod.daytime);

  // 1. Check if user is CURRENTLY in an event right now according to the timetable
  final currentEvents = todayEvents.where((e) {
    if (e.isDeleted || e.eventType == 'reminder') return false;
    final start = TimezoneService.instance.toActiveTime(e.startTime, settings);
    final end = TimezoneService.instance.toActiveTime(e.endTime, settings);
    return !now.isBefore(start) && now.isBefore(end);
  }).toList()
    ..sort((a, b) => b.endTime.compareTo(a.endTime));

  if (currentEvents.isNotEmpty) {
    final currentEvent = currentEvents.first;
    final currentEnd = TimezoneService.instance.toActiveTime(currentEvent.endTime, settings);
    final remainingMinutes = currentEnd.difference(now).inMinutes;
    final endFormatted = DateFormat('h:mm a').format(currentEnd);

    // Check what to do after current event ends
    final afterEvents = todayEvents.where((e) {
      if (e.isDeleted || e.eventType == 'reminder') return false;
      final start = TimezoneService.instance.toActiveTime(e.startTime, settings);
      return !start.isBefore(currentEnd);
    }).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final nextAfter = afterEvents.isNotEmpty ? afterEvents.first : null;
    String whatNextText;
    if (nextAfter != null) {
      final nextStart = TimezoneService.instance.toActiveTime(nextAfter.startTime, settings);
      final gap = nextStart.difference(currentEnd).inMinutes;
      final startFmt = DateFormat('h:mm a').format(nextStart);
      if (gap <= 5) {
        whatNextText = 'Followed immediately by "${nextAfter.title}" at $startFmt.';
      } else {
        whatNextText = 'Next: "${nextAfter.title}" at $startFmt (${gap}m break).';
      }
    } else {
      whatNextText = 'Open time after this event ends.';
    }

    final (badgeText, quoteItem) = switch (period) {
      SmartSuggestionPeriod.night => ('EVENING IN EVENT', HeroQuote.getEveningQuote(now)),
      SmartSuggestionPeriod.morning => ('MORNING IN EVENT', HeroQuote.getMorningQuote(now)),
      SmartSuggestionPeriod.daytime => ('WHAT TO DO NEXT', null),
    };

    return SmartSuggestion(
      freeDuration: Duration.zero,
      title: 'In Event: ${currentEvent.title}',
      description: 'Ends at $endFormatted (${remainingMinutes}m remaining). $whatNextText',
      actionLabel: 'View Schedule',
      category: currentEvent.category,
      hasFreeTime: false,
      period: period,
      badgeLabel: badgeText,
      quote: quoteItem?.text,
      quoteAuthor: quoteItem?.author,
    );
  }

  // 2. User is NOT currently in an event. Look for the next upcoming event today.
  final upcomingEvents = todayEvents
      .where((e) {
        if (e.isDeleted || e.eventType == 'reminder') return false;
        final start = TimezoneService.instance.toActiveTime(e.startTime, settings);
        return start.isAfter(now);
      })
      .toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));

  final nextEvent = upcomingEvents.isNotEmpty ? upcomingEvents.first : null;
  final nextEventStart = nextEvent != null
      ? TimezoneService.instance.toActiveTime(nextEvent.startTime, settings)
      : null;
  final freeMinutes = nextEventStart != null
      ? nextEventStart.difference(now).inMinutes
      : 120;

  if (nextEvent != null && freeMinutes < 15) {
    final (badgeText, quoteItem) = switch (period) {
      SmartSuggestionPeriod.night => ('EVENING WRAP-UP', HeroQuote.getEveningQuote(now)),
      SmartSuggestionPeriod.morning => ('MORNING KICKOFF', HeroQuote.getMorningQuote(now)),
      SmartSuggestionPeriod.daytime => ('UPCOMING EVENT', null),
    };

    return SmartSuggestion(
      freeDuration: Duration(minutes: freeMinutes.clamp(0, 15)),
      title: 'Upcoming: ${nextEvent.title}',
      description: 'Starts in $freeMinutes minutes (${DateFormat('h:mm a').format(nextEventStart!)}). Prepare your materials.',
      actionLabel: 'View Event',
      category: nextEvent.category,
      hasFreeTime: false,
      period: period,
      badgeLabel: badgeText,
      quote: quoteItem?.text,
      quoteAuthor: quoteItem?.author,
    );
  }

  // 3. User HAS free time (>= 15 minutes).
  // Prioritize habits and tasks with closest deadlines, including uncompleted daily habits.
  final freeText = '${freeMinutes ~/ 60 > 0 ? '${freeMinutes ~/ 60}h ' : ''}${freeMinutes % 60}m';

  final candidates = <_CandidateItem>[];

  // A. Check incomplete tasks
  for (final task in tasks) {
    final due = TimezoneService.instance.toActiveTime(task.dueDate, settings);
    if (due.isBefore(now)) {
      // Overdue task
      final diff = now.difference(due);
      final hoursOverdue = (diff.inMinutes / 60).round();
      final urgencyText = diff.inMinutes < 5
          ? 'Overdue!'
          : hoursOverdue < 24
              ? 'Overdue by ${hoursOverdue}h!'
              : 'Overdue by ${(diff.inHours / 24).round()}d!';
      candidates.add(
        _CandidateItem(
          effectiveDeadline: due,
          priorityRank: 1, // Overdue tasks have highest priority
          suggestion: SmartSuggestion(
            freeDuration: Duration(minutes: freeMinutes),
            title: 'Focus: ${task.title}',
            description: 'You have $freeText free. $urgencyText (was due ${DateFormat('MMM d, h:mm a').format(due)}).',
            actionLabel: 'Open Task',
            category: task.category,
            hasFreeTime: true,
            task: task,
          ),
        ),
      );
    } else {
      // Future task
      final diff = due.difference(now);
      final hoursUntil = (diff.inMinutes / 60).round();
      final minutesUntil = diff.inMinutes;

      int rank;
      String urgencyText;
      if (diff.inHours < 3) {
        rank = 2; // Imminent task due within 3 hours
        urgencyText = hoursUntil == 0
            ? 'Due in ${minutesUntil}m (${DateFormat('h:mm a').format(due)})'
            : 'Due in ${hoursUntil}h (${DateFormat('h:mm a').format(due)})';
      } else if (diff.inHours < 24) {
        rank = 3; // Due within 24 hours
        urgencyText = hoursUntil == 0
            ? 'Due in ${minutesUntil}m (${DateFormat('h:mm a').format(due)})'
            : 'Due in ${hoursUntil}h (${DateFormat('h:mm a').format(due)})';
      } else if (diff.inHours < 72) {
        final days = (diff.inHours / 24).round();
        rank = 5; // Due within 3 days
        urgencyText = 'Due in ${days}d (${DateFormat('EEE, h:mm a').format(due)})';
      } else {
        rank = 7; // Due later
        urgencyText = 'Due ${DateFormat('MMM d').format(due)}';
      }

      candidates.add(
        _CandidateItem(
          effectiveDeadline: due,
          priorityRank: rank,
          suggestion: SmartSuggestion(
            freeDuration: Duration(minutes: freeMinutes),
            title: 'Focus: ${task.title}',
            description: 'You have $freeText free. $urgencyText.',
            actionLabel: 'Open Task',
            category: task.category,
            hasFreeTime: true,
            task: task,
          ),
        ),
      );
    }
  }

  // B. Check active habits
  final isWeekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
  final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);

  // End of current week (Sunday 23:59:59)
  final daysUntilSunday = (7 - (now.weekday % 7)) % 7;
  final weekEnd = DateTime(now.year, now.month, now.day + daysUntilSunday, 23, 59, 59);

  for (final habit in habits) {
    // Days filter check
    if (habit.daysFilter == 'weekdays' && isWeekend) continue;
    if (habit.daysFilter == 'weekends' && !isWeekend) continue;

    final isDaily = habit.targetFrequencyPerWeek >= 7;
    final completedToday = todayHabitCounts[habit.id] ?? 0;
    final completedThisWeek = habitCounts[habit.id] ?? 0;

    if (isDaily && completedToday == 0) {
      // Uncompleted daily habit! Effective deadline is end of today.
      Event? scheduledLater;
      for (final e in todayEvents) {
        final start = TimezoneService.instance.toActiveTime(e.startTime, settings);
        if (!e.isDeleted &&
            start.isAfter(now) &&
            e.autoScheduleSource != null &&
            e.autoScheduleSource!.contains('habit:${habit.id}')) {
          scheduledLater = e;
          break;
        }
      }

      final String desc;
      final int rank;
      if (scheduledLater != null) {
        rank = 4;
        final start = TimezoneService.instance.toActiveTime(scheduledLater.startTime, settings);
        final timeStr = DateFormat('h:mm a').format(start);
        desc = 'You have $freeText free. Daily habit scheduled for $timeStr, or get ahead now.';
      } else {
        rank = 3; // Unscheduled daily habit is urgent for today
        desc = 'You have $freeText free. Daily habit not yet completed today.';
      }

      candidates.add(
        _CandidateItem(
          effectiveDeadline: todayEnd,
          priorityRank: rank,
          suggestion: SmartSuggestion(
            freeDuration: Duration(minutes: freeMinutes),
            title: 'Daily Habit: ${habit.title}',
            description: desc,
            actionLabel: 'Log Session',
            category: habit.category,
            hasFreeTime: true,
            habit: habit,
          ),
        ),
      );
    } else if (!isDaily && completedThisWeek < habit.targetFrequencyPerWeek) {
      // Uncompleted weekly habit! Effective deadline is end of week.
      candidates.add(
        _CandidateItem(
          effectiveDeadline: weekEnd,
          priorityRank: 6,
          suggestion: SmartSuggestion(
            freeDuration: Duration(minutes: freeMinutes),
            title: 'Habit: ${habit.title}',
            description: 'You have $freeText free. $completedThisWeek/${habit.targetFrequencyPerWeek} sessions done this week.',
            actionLabel: 'Log Session',
            category: habit.category,
            hasFreeTime: true,
            habit: habit,
          ),
        ),
      );
    }
  }

  if (candidates.isNotEmpty) {
    candidates.sort((a, b) {
      final rankCmp = a.priorityRank.compareTo(b.priorityRank);
      if (rankCmp != 0) return rankCmp;
      return a.effectiveDeadline.compareTo(b.effectiveDeadline);
    });
  }

  if (isNight) {
    // ─────────────── NIGHT / REWIND MODE (10:00 PM - 04:00 AM) ───────────────
    final eveningQuote = HeroQuote.getEveningQuote(now);

    // 1. Overdue task (rank 1)
    final overdueCandidate = candidates.where((c) => c.priorityRank == 1).firstOrNull;
    if (overdueCandidate != null) {
      final task = overdueCandidate.suggestion.task!;
      return SmartSuggestion(
        freeDuration: Duration(minutes: freeMinutes),
        title: 'Rewind & Wrap Up: ${task.title}',
        description: 'Overdue task pending. Wrap this up quickly or reschedule it so you can rest with peace of mind.',
        actionLabel: 'Open Task',
        category: task.category,
        hasFreeTime: true,
        task: task,
        period: SmartSuggestionPeriod.night,
        quote: eveningQuote.text,
        quoteAuthor: eveningQuote.author,
        badgeLabel: 'REWIND & WIND DOWN',
      );
    }

    // 2. Imminent task due tonight (< 3 hours)
    final imminentCandidate = candidates.where((c) => c.priorityRank == 2).firstOrNull;
    if (imminentCandidate != null) {
      final task = imminentCandidate.suggestion.task!;
      return SmartSuggestion(
        freeDuration: Duration(minutes: freeMinutes),
        title: 'Rewind & Finish: ${task.title}',
        description: '${imminentCandidate.suggestion.description} Final push before sleep.',
        actionLabel: 'Open Task',
        category: task.category,
        hasFreeTime: true,
        task: task,
        period: SmartSuggestionPeriod.night,
        quote: eveningQuote.text,
        quoteAuthor: eveningQuote.author,
        badgeLabel: 'REWIND & WIND DOWN',
      );
    }

    // 3. Uncompleted daily habit (e.g. night reading, stretch, meditation)
    final dailyHabitCandidate = candidates.where((c) =>
      c.suggestion.habit?.targetFrequencyPerWeek != null &&
      c.suggestion.habit!.targetFrequencyPerWeek >= 7
    ).firstOrNull;
    if (dailyHabitCandidate != null) {
      final habit = dailyHabitCandidate.suggestion.habit!;
      return SmartSuggestion(
        freeDuration: Duration(minutes: freeMinutes),
        title: 'Rewind: ${habit.title}',
        description: 'Wind down with your daily habit before turning in for the night.',
        actionLabel: 'Log Session',
        category: habit.category,
        hasFreeTime: true,
        habit: habit,
        period: SmartSuggestionPeriod.night,
        quote: eveningQuote.text,
        quoteAuthor: eveningQuote.author,
        badgeLabel: 'REWIND & WIND DOWN',
      );
    }

    // 4. Pure Rewind Time: No urgent tasks or habits tonight!
    // Check tomorrow's schedule for preview:
    final tomorrowDate = DateTime(now.year, now.month, now.day + 1);
    final tomorrowEvents = todayEvents.where((e) {
      if (e.isDeleted || e.eventType == 'reminder') return false;
      final start = TimezoneService.instance.toActiveTime(e.startTime, settings);
      return start.year == tomorrowDate.year &&
             start.month == tomorrowDate.month &&
             start.day == tomorrowDate.day;
    }).toList()..sort((a, b) => a.startTime.compareTo(b.startTime));

    final String rewindDetail;
    if (tomorrowEvents.isNotEmpty) {
      final firstTomorrow = tomorrowEvents.first;
      final firstStart = TimezoneService.instance.toActiveTime(firstTomorrow.startTime, settings);
      rewindDetail = 'Great job today. Tomorrow starts with "${firstTomorrow.title}" at ${DateFormat('h:mm a').format(firstStart)}. Put away bright screens, relax, and get ready for a restful sleep.';
    } else {
      rewindDetail = 'Great job getting through today. Take time to unwind, put away bright screens, and enjoy your rewind time.';
    }

    return SmartSuggestion(
      freeDuration: Duration(minutes: freeMinutes),
      title: 'Time to Rewind & Recharge',
      description: rewindDetail,
      actionLabel: 'Review Tomorrow\'s Agenda',
      category: 'personal',
      hasFreeTime: true,
      period: SmartSuggestionPeriod.night,
      quote: eveningQuote.text,
      quoteAuthor: eveningQuote.author,
      badgeLabel: 'REWIND & WIND DOWN',
    );
  }

  if (isMorning) {
    // ─────────────── MORNING KICKOFF MODE (04:00 AM - 09:00 AM) ───────────────
    final morningQuote = HeroQuote.getMorningQuote(now);

    // 1. Overdue task to clear first
    final overdueCandidate = candidates.where((c) => c.priorityRank == 1).firstOrNull;
    if (overdueCandidate != null) {
      final task = overdueCandidate.suggestion.task!;
      return SmartSuggestion(
        freeDuration: Duration(minutes: freeMinutes),
        title: 'Morning Win: ${task.title}',
        description: 'Start your morning with a quick win by tackling this overdue task before your day gets busy.',
        actionLabel: 'Open Task',
        category: task.category,
        hasFreeTime: true,
        task: task,
        period: SmartSuggestionPeriod.morning,
        quote: morningQuote.text,
        quoteAuthor: morningQuote.author,
        badgeLabel: 'GET READY FOR THE DAY',
      );
    }

    // Today's upcoming events:
    final morningEvents = todayEvents.where((e) {
      if (e.isDeleted || e.eventType == 'reminder') return false;
      final start = TimezoneService.instance.toActiveTime(e.startTime, settings);
      return start.year == now.year &&
             start.month == now.month &&
             start.day == now.day &&
             start.isAfter(now);
    }).toList()..sort((a, b) => a.startTime.compareTo(b.startTime));

    final dailyHabitCandidate = candidates.where((c) =>
      c.suggestion.habit?.targetFrequencyPerWeek != null &&
      c.suggestion.habit!.targetFrequencyPerWeek >= 7
    ).firstOrNull;

    final String morningDetail;
    if (morningEvents.isNotEmpty) {
      final first = morningEvents.first;
      final startFmt = DateFormat('h:mm a').format(TimezoneService.instance.toActiveTime(first.startTime, settings));
      morningDetail = 'You have ${morningEvents.length} event(s) scheduled today, starting with "${first.title}" at $startFmt. Hydrate, review your materials, and set your morning intentions.';
    } else {
      morningDetail = 'Clear slate today! Take time for your morning routine, review your goals, and set your top 3 priorities for the day.';
    }

    return SmartSuggestion(
      freeDuration: Duration(minutes: freeMinutes),
      title: 'Rise & Shine: Ready for Today',
      description: morningDetail,
      actionLabel: 'View Today\'s Agenda',
      category: 'personal',
      hasFreeTime: true,
      habit: dailyHabitCandidate?.suggestion.habit,
      period: SmartSuggestionPeriod.morning,
      quote: morningQuote.text,
      quoteAuthor: morningQuote.author,
      badgeLabel: 'GET READY FOR THE DAY',
    );
  }

  // ─────────────── DAYTIME MODE (09:00 AM - 10:00 PM) ───────────────
  if (candidates.isNotEmpty) {
    return candidates.first.suggestion;
  }

  return SmartSuggestion(
    freeDuration: Duration(minutes: freeMinutes),
    title: 'Great job! You\'re all caught up',
    description: 'You have $freeText of open time today.',
    actionLabel: 'Plan Ahead',
    category: 'personal',
    hasFreeTime: true,
    period: SmartSuggestionPeriod.daytime,
    badgeLabel: 'WHAT TO DO NEXT',
  );
});

class _CandidateItem {
  final DateTime effectiveDeadline;
  final int priorityRank;
  final SmartSuggestion suggestion;

  _CandidateItem({
    required this.effectiveDeadline,
    required this.priorityRank,
    required this.suggestion,
  });
}

