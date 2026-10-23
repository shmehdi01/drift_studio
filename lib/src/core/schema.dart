/// The kind of a `sqlite_master` entry.
enum DbObjectType {
  /// A regular table.
  table,

  /// A view.
  view,

  /// An index. (`index` is reserved by [Enum.index].)
  sqlIndex,

  /// A trigger.
  trigger;

  /// Parses the `type` column of `sqlite_master`.
  static DbObjectType parse(String raw) => switch (raw) {
        'view' => DbObjectType.view,
        'index' => DbObjectType.sqlIndex,
        'trigger' => DbObjectType.trigger,
        _ => DbObjectType.table,
      };
}

/// One column of a table or view, from `PRAGMA table_info`.
class ColumnInfo {
  /// Creates column metadata.
  const ColumnInfo({
    required this.position,
    required this.name,
    required this.declaredType,
    required this.notNull,
    required this.defaultValue,
    required this.primaryKeyIndex,
  });

  /// Zero-based column position.
  final int position;

  /// Column name.
  final String name;

  /// The type as written in the `CREATE` statement (may be empty).
  final String declaredType;

  /// Whether the column has a `NOT NULL` constraint.
  final bool notNull;

  /// The default value expression, if any.
  final String? defaultValue;

  /// 1-based position inside the primary key, or 0 if not part of it.
  final int primaryKeyIndex;

  /// Whether this column is part of the primary key.
  bool get isPrimaryKey => primaryKeyIndex > 0;

  /// The SQLite type affinity derived from [declaredType] using SQLite's
  /// documented rules, which is what actually governs stored values.
  ColumnAffinity get affinity => ColumnAffinity.fromDeclaredType(declaredType);
}

/// SQLite type affinity (https://sqlite.org/datatype3.html#type_affinity).
enum ColumnAffinity {
  /// INTEGER affinity.
  integer,

  /// TEXT affinity.
  text,

  /// BLOB affinity.
  blob,

  /// REAL affinity.
  real,

  /// NUMERIC affinity.
  numeric;

  /// Applies SQLite's affinity rules to a declared type.
  static ColumnAffinity fromDeclaredType(String declared) {
    final t = declared.toUpperCase();
    if (t.contains('INT')) return ColumnAffinity.integer;
    if (t.contains('CHAR') || t.contains('CLOB') || t.contains('TEXT')) {
      return ColumnAffinity.text;
    }
    if (t.isEmpty || t.contains('BLOB')) return ColumnAffinity.blob;
    if (t.contains('REAL') || t.contains('FLOA') || t.contains('DOUB')) {
      return ColumnAffinity.real;
    }
    return ColumnAffinity.numeric;
  }

  /// Whether values of this affinity should be right-aligned like numbers.
  bool get isNumeric =>
      this == integer || this == real || this == ColumnAffinity.numeric;
}

/// An index, from `PRAGMA index_list` + `PRAGMA index_info`.
class IndexInfo {
  /// Creates index metadata.
  const IndexInfo({
    required this.name,
    required this.unique,
    required this.origin,
    required this.columns,
  });

  /// Index name.
  final String name;

  /// Whether the index enforces uniqueness.
  final bool unique;

  /// `c` (CREATE INDEX), `u` (UNIQUE constraint) or `pk` (primary key).
  final String origin;

  /// Indexed column names in key order.
  final List<String> columns;
}

/// A foreign key, from `PRAGMA foreign_key_list`.
class ForeignKeyInfo {
  /// Creates foreign key metadata.
  const ForeignKeyInfo({
    required this.fromColumn,
    required this.table,
    required this.toColumn,
    required this.onUpdate,
    required this.onDelete,
  });

  /// Column in the owning table.
  final String fromColumn;

  /// Referenced table.
  final String table;

  /// Referenced column (may be null when it targets the primary key).
  final String? toColumn;

  /// `ON UPDATE` action.
  final String onUpdate;

  /// `ON DELETE` action.
  final String onDelete;
}

/// A table, view, index or trigger in the database.
class DbObject {
  /// Creates an object entry from `sqlite_master`.
  const DbObject({
    required this.name,
    required this.type,
    required this.tableName,
    required this.sql,
  });

  /// Object name.
  final String name;

  /// Object kind.
  final DbObjectType type;

  /// The table this object belongs to (same as [name] for tables).
  final String tableName;

  /// The original `CREATE` statement, if SQLite stored one.
  final String? sql;

  /// Whether rows can be browsed (tables and views).
  bool get isBrowsable =>
      type == DbObjectType.table || type == DbObjectType.view;

  /// Whether this is an SQLite-internal object such as `sqlite_sequence`.
  bool get isInternal => name.startsWith('sqlite_');
}

/// Detailed structure of a single table or view.
class TableDetails {
  /// Creates table details.
  const TableDetails({
    required this.object,
    required this.columns,
    required this.indexes,
    required this.foreignKeys,
    required this.triggers,
  });

  /// The underlying `sqlite_master` entry.
  final DbObject object;

  /// Columns in declaration order.
  final List<ColumnInfo> columns;

  /// Indexes defined on the table.
  final List<IndexInfo> indexes;

  /// Outgoing foreign keys.
  final List<ForeignKeyInfo> foreignKeys;

  /// Triggers attached to the table.
  final List<DbObject> triggers;

  /// Primary key columns in key order.
  List<ColumnInfo> get primaryKey =>
      columns.where((c) => c.isPrimaryKey).toList()
        ..sort((a, b) => a.primaryKeyIndex.compareTo(b.primaryKeyIndex));

  /// Looks up a column by name.
  ColumnInfo? column(String name) {
    for (final c in columns) {
      if (c.name == name) return c;
    }
    return null;
  }
}

/// Database-level facts shown in the studio header.
class DatabaseInfo {
  /// Creates database info.
  const DatabaseInfo({
    required this.sqliteVersion,
    required this.userVersion,
    required this.pageSize,
    required this.pageCount,
    required this.journalMode,
    required this.foreignKeysEnabled,
  });

  /// `sqlite_version()`.
  final String sqliteVersion;

  /// `PRAGMA user_version` — Drift stores its `schemaVersion` here.
  final int userVersion;

  /// `PRAGMA page_size`.
  final int pageSize;

  /// `PRAGMA page_count`.
  final int pageCount;

  /// `PRAGMA journal_mode`.
  final String journalMode;

  /// `PRAGMA foreign_keys`.
  final bool foreignKeysEnabled;

  /// Approximate on-disk size of the main database file.
  int get sizeInBytes => pageSize * pageCount;
}
