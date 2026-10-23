import 'package:drift_studio/drift_studio.dart';
import 'package:drift_studio/src/controllers/sql_console_controller.dart';
import 'package:drift_studio/src/controllers/studio_controller.dart';
import 'package:drift_studio/src/controllers/table_data_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  late TestDatabase db;
  late DriftStudioDataSource source;

  setUp(() async {
    db = TestDatabase();
    await db.seed();
    source = DriftStudioDataSource(db);
  });

  tearDown(() => db.close());

  test('inspector lists objects and describes tables', () async {
    final inspector = SchemaInspector(source);
    final objects = await inspector.listObjects();
    final names = objects.map((o) => o.name);
    expect(
        names,
        containsAll([
          'customers',
          'orders',
          'big_orders',
          'weird table',
          'idx_orders_customer'
        ]));

    final orders = objects.firstWhere((o) => o.name == 'orders');
    final d = await inspector.describe(orders, objects);
    expect(
        d.columns.map((c) => c.name), ['id', 'customer_id', 'total', 'note']);
    expect(d.primaryKey.single.name, 'id');
    expect(d.foreignKeys.single.table, 'customers');
    expect(d.foreignKeys.single.onDelete, 'CASCADE');
    expect(d.indexes.single.columns, ['customer_id']);

    final info = await inspector.databaseInfo();
    expect(info.userVersion, 3);
    expect(await inspector.countRows('weird table'), 0);
  });

  test('grid controller pages, searches, filters and sorts', () async {
    final inspector = SchemaInspector(source);
    final objects = await inspector.listObjects();
    final details = await inspector.describe(
        objects.firstWhere((o) => o.name == 'customers'), objects);
    final grid = TableDataController(
        source: source, details: details, pageSize: 50, allowWrites: true);
    await grid.reload();

    expect(grid.result.rows, hasLength(50));
    expect(grid.totalRows, 120);
    expect(grid.pageCount, 3);

    await grid.goToPage(2);
    expect(grid.result.rows, hasLength(20));

    await grid.setSearch('Customer 11');
    expect(grid.totalRows, 11); // 11, 110..119
    await grid.setSearch('');

    await grid.addFilter(
        const ColumnFilter(column: 'email', operator: FilterOperator.isNull));
    expect(grid.totalRows, 60);
    await grid.toggleSort('id');
    await grid.toggleSort('id');
    expect(grid.result.rowAsMap(0)['id'], 119);

    await grid.updateCell(0, 'name', 'Renamed');
    expect(grid.result.rowAsMap(0)['name'], 'Renamed');
    await grid.deleteRow(0);
    expect(grid.totalRows, 59);
    grid.dispose();
  });

  test('search treats % and _ literally', () async {
    final inspector = SchemaInspector(source);
    final objects = await inspector.listObjects();
    final details = await inspector.describe(
        objects.firstWhere((o) => o.name == 'orders'), objects);
    final grid = TableDataController(
        source: source, details: details, pageSize: 50, allowWrites: false);
    await grid.setSearch('50%_');
    expect(grid.totalRows, 119);
    expect(grid.canEdit, isFalse);
    grid.dispose();
  });

  test('console blocks writes in read-only mode and runs scripts otherwise',
      () async {
    var writes = 0;
    final readOnly = SqlConsoleController(
      source: source,
      config: const DriftStudioConfig(),
      onWrite: ({required schemaChanged}) async => writes++,
    );
    await readOnly.run(sql: 'DELETE FROM orders');
    expect(readOnly.error, isA<WritesDisabledException>());
    await readOnly.run(
        sql: 'SELECT COUNT(*) AS n FROM orders; SELECT 1 AS one');
    expect(readOnly.result!.columns, ['one']);
    expect(readOnly.statementCount, 2);
    expect(readOnly.history.first, contains('SELECT 1'));
    readOnly.dispose();

    final writable = SqlConsoleController(
      source: source,
      config: const DriftStudioConfig(allowWrites: true),
      onWrite: ({required schemaChanged}) async => writes++,
    );
    var asked = false;
    await writable.run(
      sql:
          "UPDATE orders SET note = 'x' WHERE id <= 3; SELECT COUNT(*) AS n FROM orders WHERE note = 'x'",
      confirm: (s) async => asked = true,
    );
    expect(asked, isTrue);
    expect(writable.error, isNull);
    expect(writable.result!.rows.single.single, 3);
    expect(writable.result!.affectedRows, 3);
    expect(writes, 1);

    await writable.run(
        sql: 'INSERT INTO customers (name) VALUES (\'r\') RETURNING id',
        confirm: (_) async => true);
    expect(writable.result!.columns, ['id']);
    writable.dispose();
  });

  test('studio controller filters the sidebar by name, fuzzily and by column',
      () async {
    final studio =
        StudioController(source: source, config: const DriftStudioConfig());
    await studio.load();
    expect(studio.error, isNull);
    expect(studio.selected?.name, 'customers');

    studio.setSidebarFilter('ord');
    expect(studio.visibleObjects(DbObjectType.table).map((o) => o.name),
        ['orders']);

    studio.setSidebarFilter('cstmr');
    expect(studio.visibleObjects(DbObjectType.table).map((o) => o.name),
        ['customers']);

    studio.setSidebarFilter('email');
    expect(studio.visibleObjects(DbObjectType.table).map((o) => o.name),
        ['customers']);
    expect(studio.matchingColumns('customers'), ['email']);

    expect(studio.templateColumnOf('customers'), 'name');
    studio.dispose();
  });
}
