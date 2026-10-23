/// A named SQL snippet: built-in templates, app-provided presets and the
/// queries a user saves from the console all share this shape.
///
/// [sql] may contain `{{table}}` and `{{column}}` placeholders, which are
/// filled from the table and first column selected in the studio when the
/// snippet is inserted.
class SavedQuery {
  /// Creates a snippet.
  const SavedQuery({
    required this.id,
    required this.title,
    required this.sql,
    this.description,
    this.group = 'Custom',
  });

  /// Restores a snippet from [toJson] output.
  factory SavedQuery.fromJson(Map<String, Object?> json) => SavedQuery(
        id: json['id']! as String,
        title: json['title']! as String,
        sql: json['sql']! as String,
        description: json['description'] as String?,
        group: (json['group'] as String?) ?? 'Saved',
      );

  /// Stable identifier, used for de-duplication and deletion.
  final String id;

  /// Short display name.
  final String title;

  /// SQL text, optionally with placeholders.
  final String sql;

  /// Optional explanation shown under the title.
  final String? description;

  /// Section the snippet is listed under.
  final String group;

  /// Whether the SQL contains placeholders that need a selected table.
  bool get isTemplate => sql.contains('{{');

  /// Substitutes placeholders. Identifiers are quoted so names with spaces
  /// or keywords still produce valid SQL.
  String resolve({String? table, String? column}) {
    String q(String v) => '"${v.replaceAll('"', '""')}"';
    var out = sql;
    if (table != null) out = out.replaceAll('{{table}}', q(table));
    if (column != null) out = out.replaceAll('{{column}}', q(column));
    return out;
  }

  /// Serialises the snippet for a [QueryStore].
  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'sql': sql,
        if (description != null) 'description': description,
        'group': group,
      };
}

/// Persistence for user-saved queries and run history.
///
/// The default [InMemoryQueryStore] forgets everything when the studio is
/// closed. Implement this with `shared_preferences`, a file or your own
/// Drift table to keep queries across sessions — see the README.
abstract class QueryStore {
  /// Loads saved queries.
  Future<List<SavedQuery>> loadSaved();

  /// Persists the full list of saved queries.
  Future<void> writeSaved(List<SavedQuery> queries);

  /// Loads run history, newest first.
  Future<List<String>> loadHistory();

  /// Persists run history, newest first.
  Future<void> writeHistory(List<String> history);
}

/// A [QueryStore] that keeps everything in memory.
///
/// Keep a single instance alive (for example as a top-level `final`) to
/// retain saved queries while the app is running.
class InMemoryQueryStore implements QueryStore {
  List<SavedQuery> _saved = [];
  List<String> _history = [];

  @override
  Future<List<SavedQuery>> loadSaved() async => List.of(_saved);

  @override
  Future<void> writeSaved(List<SavedQuery> queries) async =>
      _saved = List.of(queries);

  @override
  Future<List<String>> loadHistory() async => List.of(_history);

  @override
  Future<void> writeHistory(List<String> history) async =>
      _history = List.of(history);
}

/// Templates that ship with the studio. They work on any table.
abstract final class BuiltInQueries {
  /// Generic templates using `{{table}}` / `{{column}}` placeholders.
  static const templates = <SavedQuery>[
    SavedQuery(
      id: 'builtin.select',
      group: 'Templates',
      title: 'Browse rows',
      description: 'First 100 rows of the selected table',
      sql: 'SELECT *\nFROM {{table}}\nLIMIT 100;',
    ),
    SavedQuery(
      id: 'builtin.latest',
      group: 'Templates',
      title: 'Latest rows',
      description: 'Most recently inserted rows (by rowid)',
      sql: 'SELECT *\nFROM {{table}}\nORDER BY rowid DESC\nLIMIT 50;',
    ),
    SavedQuery(
      id: 'builtin.count',
      group: 'Templates',
      title: 'Count rows',
      sql: 'SELECT COUNT(*) AS total\nFROM {{table}};',
    ),
    SavedQuery(
      id: 'builtin.distinct',
      group: 'Templates',
      title: 'Value distribution',
      description: 'How often each value appears in a column',
      sql: 'SELECT {{column}}, COUNT(*) AS occurrences\n'
          'FROM {{table}}\n'
          'GROUP BY {{column}}\n'
          'ORDER BY occurrences DESC\n'
          'LIMIT 100;',
    ),
    SavedQuery(
      id: 'builtin.duplicates',
      group: 'Templates',
      title: 'Find duplicates',
      description: 'Values that appear more than once in a column',
      sql: 'SELECT {{column}}, COUNT(*) AS copies\n'
          'FROM {{table}}\n'
          'GROUP BY {{column}}\n'
          'HAVING COUNT(*) > 1\n'
          'ORDER BY copies DESC;',
    ),
    SavedQuery(
      id: 'builtin.nulls',
      group: 'Templates',
      title: 'Rows with NULL',
      description: 'Rows where the first column is NULL',
      sql: 'SELECT *\nFROM {{table}}\nWHERE {{column}} IS NULL\nLIMIT 100;',
    ),
    SavedQuery(
      id: 'builtin.columns',
      group: 'Schema',
      title: 'Table columns',
      sql: 'PRAGMA table_info({{table}});',
    ),
    SavedQuery(
      id: 'builtin.indexes',
      group: 'Schema',
      title: 'Table indexes',
      sql: 'PRAGMA index_list({{table}});',
    ),
    SavedQuery(
      id: 'builtin.fks',
      group: 'Schema',
      title: 'Foreign keys',
      sql: 'PRAGMA foreign_key_list({{table}});',
    ),
    SavedQuery(
      id: 'builtin.all_tables',
      group: 'Schema',
      title: 'All tables & views',
      sql: 'SELECT type, name, sql\nFROM sqlite_master\n'
          "WHERE type IN ('table', 'view')\nORDER BY name;",
    ),
    SavedQuery(
      id: 'builtin.integrity',
      group: 'Diagnostics',
      title: 'Integrity check',
      sql: 'PRAGMA integrity_check;',
    ),
    SavedQuery(
      id: 'builtin.fk_check',
      group: 'Diagnostics',
      title: 'Foreign key violations',
      sql: 'PRAGMA foreign_key_check;',
    ),
    SavedQuery(
      id: 'builtin.version',
      group: 'Diagnostics',
      title: 'Schema & SQLite version',
      sql: 'SELECT sqlite_version() AS sqlite,\n'
          '       (SELECT user_version FROM pragma_user_version) AS schema_version;',
    ),
  ];
}
