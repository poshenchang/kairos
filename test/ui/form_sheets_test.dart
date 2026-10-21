// test/ui/form_sheets_test.dart
//
// Shared create/edit sheets for tasks and habits: nothing is written until
// Save, presets update the visible dropdowns, and both fit a phone screen.

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/core/scheduler/scheduler_provider.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/ui/widgets/habit_form_sheet.dart';
import 'package:kairos/ui/widgets/task_form_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  // Drift completes on real async I/O, so alternate real waits with pumps.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Pumps a phone-sized app with a button that opens the sheet via [open].
  Future<void> pumpOpener(WidgetTester tester, void Function(BuildContext) open) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(onPressed: () => open(context), child: const Text('open')),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  Future<T> io<T>(WidgetTester tester, Future<T> Function() fn) async => (await tester.runAsync(fn)) as T;

  Future<Task> insertTaskWithSubtask(WidgetTester tester) => io(tester, () async {
        final id = await db.taskDao.insertTask(TasksCompanion.insert(
          title: 'Report',
          dueDate: DateTime.now().toUtc().add(const Duration(days: 3)),
        ));
        await db.taskDao.insertSubtask(SubtasksCompanion.insert(taskId: id, title: 'Outline'));
        return (await db.taskDao.getTaskById(id))!;
      });

  testWidgets('task edits, including subtasks, are discarded when closed without saving', (tester) async {
    final task = await insertTaskWithSubtask(tester);
    await pumpOpener(tester, (c) => TaskFormSheet.show(c, task: task));

    expect(tester.takeException(), isNull);
    expect(find.text('Outline'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Add subtask (e.g. outline draft)...'), 'Draft');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.tap(find.byTooltip('Remove subtask').first); // removes "Outline"
    await tester.pump();
    await tester.tap(find.byTooltip('Discard'));
    await settle(tester);

    final subtasks = await io(tester, () => db.taskDao.getSubtasksForTask(task.id));
    expect(subtasks.map((s) => s.title), ['Outline']);
    await unmount(tester);
  });

  testWidgets('saving a task applies title and subtask changes', (tester) async {
    final task = await insertTaskWithSubtask(tester);
    await pumpOpener(tester, (c) => TaskFormSheet.show(c, task: task));

    await tester.enterText(find.widgetWithText(TextFormField, 'Title'), 'Final Report');
    await tester.tap(find.byTooltip('Remove subtask').first);
    await tester.enterText(find.widgetWithText(TextField, 'Add subtask (e.g. outline draft)...'), 'Draft');
    await tester.tap(find.byTooltip('Add subtask'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save Changes'));
    await tester.tap(find.text('Save Changes'));
    await settle(tester);

    final saved = await io(tester, () => db.taskDao.getTaskById(task.id));
    final subtasks = await io(tester, () => db.taskDao.getSubtasksForTask(task.id));
    expect(saved!.title, 'Final Report');
    expect(subtasks.map((s) => s.title), ['Draft']);
    await unmount(tester);
  });

  testWidgets('new task form fits a phone screen', (tester) async {
    await pumpOpener(tester, (c) => TaskFormSheet.show(c));
    expect(tester.takeException(), isNull);
    expect(find.text('New Task'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('habit preset updates the visible dropdowns and saves', (tester) async {
    await pumpOpener(tester, (c) => HabitFormSheet.show(c));
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Daily Reading')); // chips scroll horizontally
    await tester.pump();
    await tester.tap(find.text('Daily Reading'));
    await tester.pump();
    expect(find.text('🌙 Evening (17:00–22:00)'), findsOneWidget);

    await tester.ensureVisible(find.text('Add Habit'));
    await tester.tap(find.text('Add Habit'));
    await settle(tester);

    final habit = (await io(tester, () => db.habitDao.getAllHabits())).single;
    expect(habit.title, 'Daily Reading / Paper Review');
    expect(habit.targetFrequencyPerWeek, 7);
    expect(habit.preferredWindow, 'evening');
    await unmount(tester);
  });

  testWidgets('editing a habit shows the active switch and saves', (tester) async {
    final habit = await io(tester, () async {
      final id = await db.habitDao.insertHabit(HabitsCompanion.insert(title: 'Piano', targetFrequencyPerWeek: const Value(3)));
      return (await db.habitDao.getAllHabits()).firstWhere((h) => h.id == id);
    });
    await pumpOpener(tester, (c) => HabitFormSheet.show(c, habit: habit));
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Active in Schedule Assistant'));
    await tester.tap(find.text('Active in Schedule Assistant'));
    await tester.tap(find.text('Save Changes'));
    await settle(tester);

    final saved = (await io(tester, () => db.habitDao.getAllHabits())).single;
    expect(saved.isActive, isFalse);
    expect(saved.targetFrequencyPerWeek, 3);
    await unmount(tester);
  });
}
