import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_studio/drift_studio.dart';
import 'package:flutter/material.dart' hide Table;

/// Kept at top level so saved queries survive closing and reopening the
/// studio while the app runs. Swap in a persistent [QueryStore] in real apps.
final queryStore = InMemoryQueryStore();

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drift Studio Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final db = DemoDatabase();

  @override
  void dispose() {
    db.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DriftStudio(
      database: db,
      config: DriftStudioConfig(
        title: 'Demo POS database',
        allowWrites: true,
        queryStore: queryStore,
        presetQueries: const [
          SavedQuery(
            id: 'app.top_customers',
            group: 'App queries',
            title: 'Top customers',
            description: 'Customers ranked by total spend',
            sql:
                'SELECT c.name, COUNT(o.id) AS orders, ROUND(SUM(o.total), 2) AS spent\n'
                'FROM customers c\n'
                'JOIN orders o ON o.customer_id = c.id\n'
                'GROUP BY c.id\n'
                'ORDER BY spent DESC\n'
                'LIMIT 20;',
          ),
          SavedQuery(
            id: 'app.unsynced',
            group: 'App queries',
            title: 'Unsynced orders',
            description: 'Orders still waiting in the outbox',
            sql:
                "SELECT * FROM orders WHERE sync_status != 'synced' ORDER BY created_at DESC;",
          ),
          SavedQuery(
            id: 'app.daily_sales',
            group: 'App queries',
            title: 'Daily sales',
            sql: "SELECT date(created_at, 'unixepoch') AS day,\n"
                '       COUNT(*) AS orders,\n'
                '       ROUND(SUM(total), 2) AS revenue\n'
                'FROM orders\n'
                'GROUP BY day\n'
                'ORDER BY day DESC;',
          ),
        ],
      ),
    );
  }
}

/// A demo database built with raw SQL so the example needs no codegen.
/// Your app passes its own generated Drift database instead.
class DemoDatabase extends GeneratedDatabase {
  DemoDatabase() : super(NativeDatabase.memory());

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          // One by one, not in a batch: drift prepares every batched statement
          // up front, and an index can't be prepared before its table exists.
          for (final s in _schema) {
            await customStatement(s);
          }
          await _seed();
        },
      );

  static const _schema = [
    'CREATE TABLE categories (id INTEGER PRIMARY KEY, name TEXT NOT NULL UNIQUE)',
    'CREATE TABLE products (id INTEGER PRIMARY KEY, sku TEXT NOT NULL UNIQUE, '
        'name TEXT NOT NULL, category_id INTEGER REFERENCES categories(id), '
        'price REAL NOT NULL, stock INTEGER NOT NULL DEFAULT 0, attributes TEXT)',
    'CREATE TABLE customers (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, '
        'phone TEXT, email TEXT, loyalty_points INTEGER DEFAULT 0, created_at INTEGER NOT NULL)',
    'CREATE TABLE orders (id INTEGER PRIMARY KEY AUTOINCREMENT, invoice_no TEXT NOT NULL UNIQUE, '
        'customer_id INTEGER REFERENCES customers(id), total REAL NOT NULL, '
        "payment_mode TEXT NOT NULL, sync_status TEXT NOT NULL DEFAULT 'pending', "
        'created_at INTEGER NOT NULL)',
    'CREATE TABLE order_items (id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE, '
        'product_id INTEGER NOT NULL REFERENCES products(id), quantity INTEGER NOT NULL, '
        'unit_price REAL NOT NULL, discount REAL NOT NULL DEFAULT 0)',
    'CREATE INDEX idx_orders_customer ON orders(customer_id)',
    'CREATE INDEX idx_orders_sync ON orders(sync_status, created_at)',
    'CREATE INDEX idx_items_order ON order_items(order_id)',
    'CREATE VIEW order_summary AS SELECT o.id, o.invoice_no, c.name AS customer, '
        'o.total, o.payment_mode, o.sync_status FROM orders o '
        'LEFT JOIN customers c ON c.id = o.customer_id',
    'CREATE TRIGGER trg_stock AFTER INSERT ON order_items BEGIN '
        'UPDATE products SET stock = stock - NEW.quantity WHERE id = NEW.product_id; END',
  ];

  Future<void> _seed() async {
    final rnd = Random(7);
    const categories = [
      'Beverages',
      'Bakery',
      'Dairy',
      'Snacks',
      'Household',
      'Personal care',
    ];
    const first = [
      'Aarav',
      'Zara',
      'Kabir',
      'Mira',
      'Ishaan',
      'Anaya',
      'Rohan',
      'Sara',
      'Vihaan',
      'Noor',
    ];
    const last = [
      'Sharma',
      'Khan',
      'Patel',
      'Iyer',
      'Das',
      'Mehta',
      'Reddy',
      'Singh',
    ];
    const modes = ['CASH', 'CARD', 'UPI', 'WALLET'];
    const statuses = ['synced', 'synced', 'synced', 'pending', 'failed'];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await transaction(() async {
      for (var i = 0; i < categories.length; i++) {
        await customStatement('INSERT INTO categories VALUES (?, ?)', [
          i + 1,
          categories[i],
        ]);
      }
      for (var i = 1; i <= 80; i++) {
        await customStatement(
          'INSERT INTO products VALUES (?, ?, ?, ?, ?, ?, ?)',
          [
            i,
            'SKU-${1000 + i}',
            '${categories[i % categories.length]} item $i',
            i % categories.length + 1,
            (rnd.nextInt(5000) + 99) / 100,
            rnd.nextInt(300),
            i % 4 == 0
                ? '{"size": "${['S', 'M', 'L'][i % 3]}", "veg": ${i.isEven}}'
                : null,
          ],
        );
      }
      for (var i = 1; i <= 400; i++) {
        await customStatement(
          'INSERT INTO customers (name, phone, email, loyalty_points, created_at) VALUES (?, ?, ?, ?, ?)',
          [
            '${first[rnd.nextInt(first.length)]} ${last[rnd.nextInt(last.length)]}',
            i % 7 == 0 ? null : '+91 9${rnd.nextInt(899999999) + 100000000}',
            i % 3 == 0 ? 'customer$i@example.com' : null,
            rnd.nextInt(2000),
            now - rnd.nextInt(86400 * 365),
          ],
        );
      }
      for (var i = 1; i <= 1500; i++) {
        final created = now - rnd.nextInt(86400 * 60);
        await customStatement(
          'INSERT INTO orders (invoice_no, customer_id, total, payment_mode, sync_status, created_at) '
          'VALUES (?, ?, 0, ?, ?, ?)',
          [
            'INV-${(100000 + i)}',
            rnd.nextInt(10) == 0 ? null : rnd.nextInt(400) + 1,
            modes[rnd.nextInt(modes.length)],
            statuses[rnd.nextInt(statuses.length)],
            created,
          ],
        );
        final lines = rnd.nextInt(4) + 1;
        for (var l = 0; l < lines; l++) {
          await customStatement(
            'INSERT INTO order_items (order_id, product_id, quantity, unit_price, discount) '
            'SELECT ?, id, ?, price, ? FROM products WHERE id = ?',
            [
              i,
              rnd.nextInt(3) + 1,
              rnd.nextInt(4) == 0 ? 5.0 : 0.0,
              rnd.nextInt(80) + 1,
            ],
          );
        }
      }
      await customStatement(
        'UPDATE orders SET total = (SELECT ROUND(SUM(quantity * unit_price - discount), 2) '
        'FROM order_items WHERE order_id = orders.id)',
      );
    });
  }
}
