// test/ui/settings_navigation_test.dart
//
// Settings on phones: section list -> section page -> back to list.
// On wide screens the list and a section are shown side by side.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/core/scheduler/scheduler_provider.dart';
import 'package:kairos/data/database/app_database.dart';
import 'package:kairos/ui/screens/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pump();
  }

  testWidgets('phone: opening a section and going back', (tester) async {
    await pumpAt(tester, const Size(390, 844));

    expect(find.text('Cloud Sync'), findsOneWidget);
    expect(find.text('Theme Mode'), findsNothing);

    await tester.tap(find.text('Appearance'));
    await tester.pump();
    expect(find.text('Theme Mode'), findsOneWidget);
    expect(find.text('Cloud Sync'), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pump();
    expect(find.text('Theme Mode'), findsNothing);
    expect(find.text('Cloud Sync'), findsOneWidget);
  });

  testWidgets('wide: list and first section side by side', (tester) async {
    await pumpAt(tester, const Size(1280, 800));

    expect(find.text('Cloud Sync'), findsOneWidget);
    expect(find.text('Theme Mode'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
  });
}
