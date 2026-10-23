import 'package:drift_studio/drift_studio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SqlUtils.isReadOnly', () {
    test('accepts reads', () {
      expect(SqlUtils.isReadOnly('SELECT * FROM t'), isTrue);
      expect(SqlUtils.isReadOnly('  -- c\nselect 1'), isTrue);
      expect(
          SqlUtils.isReadOnly('WITH x AS (SELECT 1) SELECT * FROM x'), isTrue);
      expect(SqlUtils.isReadOnly('EXPLAIN QUERY PLAN SELECT 1'), isTrue);
      expect(SqlUtils.isReadOnly('PRAGMA user_version'), isTrue);
      expect(SqlUtils.isReadOnly('PRAGMA table_info("t")'), isTrue);
    });

    test('rejects writes', () {
      expect(SqlUtils.isReadOnly('DELETE FROM t'), isFalse);
      expect(SqlUtils.isReadOnly('update t set a = 1'), isFalse);
      expect(SqlUtils.isReadOnly('PRAGMA user_version = 4'), isFalse);
      expect(SqlUtils.isReadOnly('PRAGMA wal_checkpoint(TRUNCATE)'), isFalse);
      expect(
          SqlUtils.isReadOnly('WITH x AS (SELECT 1) DELETE FROM t'), isFalse);
      expect(SqlUtils.isReadOnly('DROP TABLE t'), isFalse);
    });

    test('ignores keywords inside string literals', () {
      expect(SqlUtils.isReadOnly("WITH x AS (SELECT 'DELETE') SELECT * FROM x"),
          isTrue);
    });
  });

  group('SqlUtils.splitStatements', () {
    test('splits on top-level semicolons only', () {
      final s = SqlUtils.splitStatements(
        "SELECT 'a;b'; SELECT \"x;y\" FROM t; -- c;\n/* d; */ SELECT 3",
      );
      expect(s, hasLength(3));
      expect(s[0], "SELECT 'a;b'");
    });

    test('keeps trigger bodies together, including CASE ... END', () {
      final s = SqlUtils.splitStatements(
        'CREATE TRIGGER tr AFTER INSERT ON t BEGIN '
        'UPDATE t SET a = CASE WHEN 1 THEN 2 END; DELETE FROM u; END; SELECT 1;',
      );
      expect(s, hasLength(2));
      expect(s.first, endsWith('END'));
    });
  });

  test('quote escapes embedded quotes', () {
    expect(SqlUtils.quote('a"b'), '"a""b"');
  });

  group('TableQuery', () {
    test('builds search, filters, sort and paging with bound args', () {
      const q = TableQuery(
        table: 'orders',
        columns: ['id', 'note'],
        search: '50%',
        filters: [
          ColumnFilter(
              column: 'total',
              operator: FilterOperator.greaterThan,
              value: '10'),
          ColumnFilter(column: 'note', operator: FilterOperator.isNull),
        ],
        sortColumn: 'total',
        sortDirection: SortDirection.descending,
        limit: 25,
        offset: 50,
      );
      final s = q.selectSql();
      expect(
        s.sql,
        'SELECT * FROM "orders" WHERE '
        '(CAST("id" AS TEXT) LIKE ? ESCAPE \'\\\' OR CAST("note" AS TEXT) LIKE ? ESCAPE \'\\\') '
        'AND "total" > ? AND "note" IS NULL ORDER BY "total" DESC LIMIT 25 OFFSET 50',
      );
      expect(s.args, [r'%50\%%', r'%50\%%', 10]);
      expect(
          q.countSql().sql, startsWith('SELECT COUNT(*) FROM "orders" WHERE'));
    });

    test('in-list filter binds every value', () {
      final where = <String>[];
      final args = <Object?>[];
      const ColumnFilter(
              column: 'id', operator: FilterOperator.inList, value: '1, 2,x')
          .writeTo(where, args);
      expect(where.single, '"id" IN (?, ?, ?)');
      expect(args, [1, 2, 'x']);
    });
  });

  group('SqlAutocomplete', () {
    final ac = SqlAutocomplete({
      'customers': [('id', 'INTEGER'), ('name', 'TEXT')],
      'orders': [
        ('id', 'INTEGER'),
        ('customer_id', 'INTEGER'),
        ('total', 'REAL')
      ],
      'weird table': [('select', 'TEXT')],
    });

    test('suggests tables after FROM, even with an empty prefix', () {
      final s = ac.suggest('SELECT * FROM ', 14);
      expect(s.map((e) => e.label), containsAll(['customers', 'orders']));
      expect(s.every((e) => e.kind == SuggestionKind.table), isTrue);
    });

    test('quotes identifiers that need it', () {
      final s = ac.suggest('SELECT * FROM wei', 17);
      expect(s.single.insertText, '"weird table"');
    });

    test('resolves aliases for qualified columns', () {
      const sql = 'SELECT o. FROM orders o';
      final s = ac.suggest(sql, 9);
      expect(s.map((e) => e.label), ['id', 'customer_id', 'total']);
    });

    test('prefers columns of tables mentioned in the query', () {
      const sql = 'SELECT to FROM orders';
      final s = ac.suggest(sql, 9);
      expect(s.first.label, 'total');
    });

    test('stays quiet on an empty prefix unless forced', () {
      expect(ac.suggest('SELECT ', 7), isEmpty);
      expect(ac.suggest('SELECT ', 7, force: true), isNotEmpty);
    });
  });

  test('SavedQuery resolves placeholders with quoted identifiers', () {
    const q = SavedQuery(
        id: 'x', title: 'x', sql: 'SELECT {{column}} FROM {{table}}');
    expect(q.resolve(table: 'weird table', column: 'a'),
        'SELECT "a" FROM "weird table"');
  });

  test('ResultExporter produces CSV and INSERTs', () {
    const r = QueryResult(columns: [
      'a',
      'b'
    ], rows: [
      [1, 'x,"y"'],
      [null, "it's"],
    ]);
    expect(ResultExporter.toCsv(r), 'a,b\n1,"x,""y"""\n,it\'s\n');
    expect(
      ResultExporter.toInserts(r, 't'),
      'INSERT INTO "t" ("a", "b") VALUES (1, \'x,"y"\');\n'
      'INSERT INTO "t" ("a", "b") VALUES (NULL, \'it\'\'s\');',
    );
  });
}
