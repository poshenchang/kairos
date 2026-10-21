// test/ui/task_card_gestures_test.dart
//
// Swipe gestures on the Tasks screen: swipe right completes, swipe left
// deletes, and both can be undone from the snackbar.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/core/scheduler/scheduler_provider.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/ui/screens/tasks/tasks_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  // Drift streams complete on real async I/O, so alternate real waits with pumps.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<int> pumpWithTask(WidgetTester tester, {bool recurring = false}) async {
    final id = (await tester.runAsync(() => db.taskDao.insertTask(TasksCompanion.insert(
          title: 'Accounting HW',
          dueDate: DateTime.now().toUtc().add(const Duration(days: 3)),
          isRecurring: Value(recurring),
          rrule: Value(recurring ? 'FREQ=WEEKLY' : null),
        ))))!;
    tester.view.physicalSize = const Size(390, 844) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: TasksScreen()),
    ));
    await settle(tester);
    return id;
  }

  // Unmount so drift's stream-cleanup timers fire before the test ends.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<Task> readTask(WidgetTester tester, int id) async =>
      (await tester.runAsync(() => (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingle()))!;

  testWidgets('swipe left deletes, UNDO restores', (tester) async {
    final id = await pumpWithTask(tester);

    await tester.drag(find.text('Accounting HW'), const Offset(-500, 0));
    await settle(tester);

    expect(find.text('Accounting HW'), findsNothing);
    expect((await readTask(tester, id)).isDeleted, isTrue);
    expect(find.text('Deleted "Accounting HW"'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await settle(tester);

    expect((await readTask(tester, id)).isDeleted, isFalse);
    expect(find.text('Accounting HW'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('swipe right completes, UNDO reverts', (tester) async {
    final id = await pumpWithTask(tester);

    await tester.drag(find.text('Accounting HW'), const Offset(500, 0));
    await settle(tester);

    expect((await readTask(tester, id)).isCompleted, isTrue);
    expect(find.text('Completed "Accounting HW"'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await settle(tester);

    expect((await readTask(tester, id)).isCompleted, isFalse);
    expect(find.text('Accounting HW'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('completing a recurring task keeps the card and UNDO restores the due date', (tester) async {
    final id = await pumpWithTask(tester, recurring: true);
    final originalDue = (await readTask(tester, id)).dueDate;

    await tester.drag(find.text('Accounting HW'), const Offset(500, 0));
    await settle(tester);

    final advanced = await readTask(tester, id);
    expect(advanced.isCompleted, isFalse);
    expect(advanced.dueDate.isAfter(originalDue), isTrue);
    expect(find.text('Accounting HW'), findsOneWidget);

    await tester.tap(find.text('UNDO'));
    await settle(tester);

    expect((await readTask(tester, id)).dueDate, originalDue);
    await unmount(tester);
  });
}
