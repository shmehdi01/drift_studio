import 'package:drift_studio/drift_studio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  late TestDatabase db;

  setUp(() async {
    db = TestDatabase();
    await db.seed();
  });

  tearDown(() => db.close());

  /// Lets real SQLite futures complete, then settles the frame.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  testWidgets('desktop layout shows tables, grid, structure and console',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: DriftStudio(database: db)));
    await settle(tester);

    expect(find.text('orders'), findsWidgets);
    expect(find.text('Customer 1'), findsOneWidget);
    expect(find.textContaining('of 120 rows'), findsOneWidget);

    await tester.tap(find.text('orders').first);
    await settle(tester);
    expect(find.textContaining('of 120 rows'), findsOneWidget);

    await tester.tap(find.text('Structure'));
    await settle(tester);
    expect(find.text('Foreign keys  ·  1'), findsOneWidget);

    await tester.tap(find.text('SQL'));
    await settle(tester);
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('Browse rows'), findsOneWidget);
  });

  testWidgets('phone layout puts the explorer in a drawer', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: DriftStudio(database: db)));
    await settle(tester);

    expect(find.byTooltip('Tables'), findsOneWidget);
    expect(find.text('Customer 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
