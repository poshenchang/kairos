// test/widget_test.dart
//
// Widget test for CategoryBadge with Social category.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kairos/ui/widgets/category_badge.dart';

void main() {
  testWidgets('CategoryBadge renders social category', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CategoryBadge(categorySlugOrName: 'social'),
          ),
        ),
      ),
    );

    expect(find.byType(CategoryBadge), findsOneWidget);
  });
}
