// test/ui/quick_add_sheet_test.dart
//
// Quick add: live preview, chip removal keeps text in the title, Add saves
// the parsed task, and input without a date hands off to the full form.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/core/scheduler/scheduler_provider.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/services/settings_service.dart';
import 'package:kairos/ui/widgets/quick_add_sheet.dart';
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

  Future<void> openSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Seed the default categories the app normally creates on first launch
    await tester.runAsync(() => db.categoryDao.insertCategory(
          CategoriesCompanion.insert(name: 'Schoolwork', slug: 'schoolwork'),
        ));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // UTC wall clock keeps stored due dates easy to assert
        settingsNotifierProvider.overrideWith(
          (ref) => SettingsNotifier.withState(const SettingsState(timezoneMode: 'manual', manualTimezoneOffsetMinutes: 0)),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(onPressed: () => QuickAddSheet.show(context), child: const Text('open')),
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

  testWidgets('typing shows a preview and Add saves the parsed task', (tester) async {
    await openSheet(tester);
    await tester.enterText(find.byType(TextField), 'HW3 fri 5pm #school weekly');
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('HW3'), findsOneWidget);
    expect(find.text('17:00'), findsOneWidget);
    expect(find.text('Repeats weekly'), findsOneWidget);

    await tester.tap(find.text('Add'));
    await settle(tester);

    final task = (await tester.runAsync(() => db.taskDao.getAllTasks()))!.single;
    final due = task.dueDate.toUtc();
    expect(task.title, 'HW3');
    expect(task.category, 'schoolwork');
    expect(task.isRecurring, isTrue);
    expect(task.rrule, 'FREQ=WEEKLY;BYDAY=FR');
    expect((due.weekday, due.hour, due.minute), (DateTime.friday, 17, 0));
    expect(find.textContaining('Added "HW3"'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('removing a chip keeps that word in the title', (tester) async {
    await openSheet(tester);
    await tester.enterText(find.byType(TextField), 'SAT prep');
    await tester.pump();
    expect(find.text('prep'), findsOneWidget); // "SAT" was read as Saturday

    await tester.tap(find.byTooltip('Keep "SAT" in the title'));
    await tester.pump();

    expect(find.text('SAT prep'), findsOneWidget);
    expect(find.textContaining('No due date yet'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('no due date: the button opens the full form prefilled', (tester) async {
    await openSheet(tester);
    await tester.enterText(find.byType(TextField), 'Read chapter 2 #school');
    await tester.pump();

    await tester.tap(find.text('Pick date'));
    await settle(tester);

    expect(find.text('New Task'), findsOneWidget);
    final title = tester.widget<TextFormField>(find.widgetWithText(TextFormField, 'Title'));
    expect(title.controller!.text, 'Read chapter 2');
    expect((await tester.runAsync(() => db.taskDao.getAllTasks()))!, isEmpty);
    await unmount(tester);
  });
}
