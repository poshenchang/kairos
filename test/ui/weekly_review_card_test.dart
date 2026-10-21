// test/ui/weekly_review_card_test.dart
//
// Dashboard "Last week" card: summary text, moving overdue tasks to today
// (with undo), and dismissing it for the week.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/core/scheduler/scheduler_provider.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/services/weekly_stats.dart';
import 'package:kairos/ui/providers/app_providers.dart';
import 'package:kairos/ui/screens/dashboard/dashboard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('shows last week, moves overdue tasks to today with undo, and dismisses', (tester) async {
    final overdueDue = DateTime.now().toUtc().subtract(const Duration(days: 3));
    final overdue = (await tester.runAsync(() async {
      final id = await db.taskDao.insertTask(TasksCompanion.insert(title: 'Late essay', dueDate: overdueDue));
      return db.taskDao.getTaskById(id);
    }))!;
    final review = WeeklyReview(
      weekStart: DateTime(2026, 10, 11),
      tasksCompleted: 4,
      habitsOnTarget: 2,
      habitsTotal: 3,
      overdueTasks: [overdue],
    );

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        settingsNotifierProvider.overrideWith(
          (ref) => SettingsNotifier.withState(const SettingsState(timezoneMode: 'manual', manualTimezoneOffsetMinutes: 0)),
        ),
        weeklyReviewProvider.overrideWith((ref) => Stream.value(review)),
      ],
      child: const MaterialApp(home: DashboardScreen()),
    ));
    await settle(tester);

    expect(find.text('Last week · Oct 11–Oct 17'), findsOneWidget);
    expect(find.text('4 tasks done · 2/3 habits on target'), findsOneWidget);
    expect(find.text('1 overdue'), findsOneWidget);

    await tester.tap(find.text('Move to today'));
    await settle(tester);
    final moved = (await tester.runAsync(() => db.taskDao.getTaskById(overdue.id)))!;
    final now = DateTime.now().toUtc();
    expect((moved.dueDate.toUtc().day, moved.dueDate.toUtc().hour, moved.dueDate.toUtc().minute), (now.day, 23, 59));

    await tester.tap(find.text('UNDO'));
    await settle(tester);
    final reverted = (await tester.runAsync(() => db.taskDao.getTaskById(overdue.id)))!;
    expect(reverted.dueDate.difference(overdue.dueDate).inSeconds.abs(), lessThan(1));

    await tester.tap(find.byTooltip('Dismiss until next week'));
    await settle(tester);
    expect(find.textContaining('Last week'), findsNothing);
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    expect(prefs.getString('weekly_review_dismissed_week'), '2026-10-11');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
