// Renders the README screenshots into ../doc/screenshots.
//
//   SCREENSHOTS=1 flutter test test/screenshots_test.dart
//
// Uses real fonts (Roboto + a system monospace font) instead of the test
// font, so the images match what users see. macOS paths are assumed.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift_studio/drift_studio.dart';
import 'package:drift_studio_example/main.dart';
import 'package:flutter/material.dart' hide Table;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _enabled = Platform.environment['SCREENSHOTS'] == '1';

Future<void> _loadFonts() async {
  final flutterRoot = File(Platform.resolvedExecutable)
      .parent
      .parent
      .parent
      .parent
      .parent
      .parent
      .path;
  final materialFonts = '$flutterRoot/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader
          .addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
  }

  await load('Roboto', [
    for (final w in ['Regular', 'Medium', 'Bold', 'Italic'])
      '$materialFonts/Roboto-$w.ttf',
  ]);
  await load('MaterialIcons', ['$materialFonts/MaterialIcons-Regular.otf']);
  await load('monospace', ['/System/Library/Fonts/SFNSMono.ttf']);
}

void main() {
  final boundary = GlobalKey();

  setUpAll(() async {
    if (_enabled) await _loadFonts();
  });

  Future<void> settle(WidgetTester tester, [int rounds = 8]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final ro =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('../doc/screenshots/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
    });
  }

  Future<DemoDatabase> pumpStudio(
    WidgetTester tester, {
    required Size size,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final db = DemoDatabase();
    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme:
            ThemeData(colorSchemeSeed: Colors.indigo, brightness: brightness),
        home: DriftStudio(
          database: db,
          config: const DriftStudioConfig(
              title: 'Demo POS database', allowWrites: true),
        ),
      ),
    ));
    await settle(tester, 20);
    return db;
  }

  Future<void> select(WidgetTester tester, String table) async {
    await tester.tap(find.text(table).first);
    await settle(tester);
  }

  testWidgets('data grid', skip: !_enabled, (tester) async {
    final db = await pumpStudio(tester, size: const Size(1440, 860));
    await select(tester, 'orders');
    await tester.tap(find.text('total').first);
    await tester.tap(find.text('total').first);
    await settle(tester);
    await shoot(tester, '1_data_grid');
    await db.close();
    tester.view.reset();
  });

  testWidgets('row inspector', skip: !_enabled, (tester) async {
    final db = await pumpStudio(tester, size: const Size(1440, 860));
    await select(tester, 'products');
    await tester.tap(find.text('SKU-1004').first);
    await settle(tester);
    await shoot(tester, '2_row_inspector');
    await db.close();
    tester.view.reset();
  });

  testWidgets('structure', skip: !_enabled, (tester) async {
    final db = await pumpStudio(tester, size: const Size(1440, 860));
    await select(tester, 'order_items');
    await tester.tap(find.text('Structure'));
    await settle(tester);
    await shoot(tester, '3_structure');
    await db.close();
    tester.view.reset();
  });

  testWidgets('sql console', skip: !_enabled, (tester) async {
    final db = await pumpStudio(tester,
        size: const Size(1440, 860), brightness: Brightness.dark);
    await tester.tap(find.text('SQL'));
    await settle(tester);
    const sql =
        'SELECT c.name, COUNT(o.id) AS orders, ROUND(SUM(o.total), 2) AS spent\n'
        'FROM customers c\nJOIN orders o ON o.customer_id = c.id\n'
        'GROUP BY c.id\nORDER BY spent DESC\nLIMIT 50;';
    await tester.enterText(find.byType(TextField).last, sql);
    await tester.tap(find.text('Run'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last,
        '$sql\n\nSELECT * FROM orders o WHERE o.pa');
    await settle(tester, 3);
    await shoot(tester, '4_sql_console');
    await db.close();
    tester.view.reset();
  });

  testWidgets('phone', skip: !_enabled, (tester) async {
    final db = await pumpStudio(tester, size: const Size(390, 844));
    await settle(tester);
    await shoot(tester, '5_phone');
    await db.close();
    tester.view.reset();
  });
}
