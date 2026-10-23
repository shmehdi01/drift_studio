import 'schema.dart';
import 'sql_utils.dart';
import 'studio_data_source.dart';

/// Reads database structure through SQLite's catalog and pragmas.
///
/// Everything here is a read, so it is safe in read-only mode.
class SchemaInspector {
  /// Creates an inspector over [source].
  const SchemaInspector(this.source);

  /// The database to inspect.
  final StudioDataSource source;

  /// Lists every table, view, index and trigger, sorted by name.
  Future<List<DbObject>> listObjects() async {
    final result = await source.select(
      'SELECT type, name, tbl_name, sql FROM sqlite_master '
      "WHERE name NOT LIKE 'sqlite_autoindex_%' ORDER BY name COLLATE NOCASE",
    );
    return [
      for (final row in result.rows)
        DbObject(
          type: DbObjectType.parse(row[0] as String),
          name: row[1] as String,
          tableName: row[2] as String,
          sql: row[3] as String?,
        ),
    ];
  }

  /// Loads columns, indexes, foreign keys and triggers for [object].
  Future<TableDetails> describe(DbObject object, List<DbObject> all) async {
    final q = SqlUtils.quote(object.name);
    final columns = await source.select('PRAGMA table_info($q)');
    final indexList = object.type == DbObjectType.table
        ? (await source.select('PRAGMA index_list($q)')).rows
        : const <List<Object?>>[];
    final fks = object.type == DbObjectType.table
        ? (await source.select('PRAGMA foreign_key_list($q)')).rows
        : const <List<Object?>>[];

    final indexes = <IndexInfo>[];
    for (final row in indexList) {
      // index_list: seq, name, unique, origin, partial
      final name = row[1] as String;
      final info =
          await source.select('PRAGMA index_info(${SqlUtils.quote(name)})');
      indexes.add(IndexInfo(
        name: name,
        unique: _asInt(row[2]) == 1,
        origin: row.length > 3 ? '${row[3]}' : 'c',
        // index_info: seqno, cid, name
        columns: [for (final c in info.rows) '${c[2] ?? '<expr>'}'],
      ));
    }

    return TableDetails(
      object: object,
      // table_info: cid, name, type, notnull, dflt_value, pk
      columns: [
        for (final r in columns.rows)
          ColumnInfo(
            position: _asInt(r[0]),
            name: r[1] as String,
            declaredType: (r[2] as String?) ?? '',
            notNull: _asInt(r[3]) == 1,
            defaultValue: r[4]?.toString(),
            primaryKeyIndex: _asInt(r[5]),
          ),
      ],
      indexes: indexes,
      // foreign_key_list: id, seq, table, from, to, on_update, on_delete, match
      foreignKeys: [
        for (final r in fks)
          ForeignKeyInfo(
            table: r[2] as String,
            fromColumn: r[3] as String,
            toColumn: r[4] as String?,
            onUpdate: '${r[5]}',
            onDelete: '${r[6]}',
          ),
      ],
      triggers: [
        for (final o in all)
          if (o.type == DbObjectType.trigger && o.tableName == object.name) o,
      ],
    );
  }

  /// Counts rows in [table].
  Future<int> countRows(String table) async {
    final r =
        await source.select('SELECT COUNT(*) FROM ${SqlUtils.quote(table)}');
    return _asInt(r.rows.first.first);
  }

  /// Reads database-level information.
  Future<DatabaseInfo> databaseInfo() async {
    Future<Object?> one(String sql) async {
      final r = await source.select(sql);
      return r.rows.isEmpty ? null : r.rows.first.first;
    }

    return DatabaseInfo(
      sqliteVersion: '${await one('SELECT sqlite_version()')}',
      userVersion: _asInt(await one('PRAGMA user_version')),
      pageSize: _asInt(await one('PRAGMA page_size')),
      pageCount: _asInt(await one('PRAGMA page_count')),
      journalMode: '${await one('PRAGMA journal_mode')}',
      foreignKeysEnabled: _asInt(await one('PRAGMA foreign_keys')) == 1,
    );
  }

  static int _asInt(Object? v) => switch (v) {
        final int i => i,
        final BigInt b => b.toInt(),
        final num n => n.toInt(),
        final String s => int.tryParse(s) ?? 0,
        _ => 0,
      };
}
