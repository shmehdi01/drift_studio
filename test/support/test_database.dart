import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// A table-less Drift database whose schema is created with raw SQL, so
/// tests need no code generation.
class TestDatabase extends GeneratedDatabase {
  TestDatabase() : super(NativeDatabase.memory());

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          for (final s in schema) {
            await customStatement(s);
          }
        },
      );

  static const schema = [
    'CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT NOT NULL, '
        'email TEXT, created_at INTEGER)',
    'CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER '
        'REFERENCES customers(id) ON DELETE CASCADE, total REAL, note TEXT)',
    'CREATE INDEX idx_orders_customer ON orders(customer_id)',
    'CREATE VIEW big_orders AS SELECT * FROM orders WHERE total > 100',
    'CREATE TABLE "weird table" ("select" TEXT, "quote""d" INTEGER)',
  ];

  Future<void> seed() async {
    for (var i = 1; i <= 120; i++) {
      await customStatement(
        'INSERT INTO customers (id, name, email, created_at) VALUES (?, ?, ?, ?)',
        [i, 'Customer $i', i.isEven ? 'c$i@example.com' : null, 1700000000 + i],
      );
      await customStatement(
        'INSERT INTO orders (customer_id, total, note) VALUES (?, ?, ?)',
        [i, i * 2.5, i == 7 ? '{"gift": true}' : '50%_off'],
      );
    }
  }
}
