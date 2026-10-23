# Drift Studio

A professional database studio that runs **inside your Flutter app** and works with any
[Drift](https://pub.dev/packages/drift) (SQLite) database: a searchable table explorer, a
fast data grid with filters and sorting, a schema inspector, and a SQL console with
autocomplete, snippets and saved queries.

![Data grid](https://raw.githubusercontent.com/shmehdi01/drift_studio/main/doc/screenshots/1_data_grid.png)

| SQL console | Row inspector |
|---|---|
| ![SQL console](https://raw.githubusercontent.com/shmehdi01/drift_studio/main/doc/screenshots/4_sql_console.png) | ![Row inspector](https://raw.githubusercontent.com/shmehdi01/drift_studio/main/doc/screenshots/2_row_inspector.png) |

## Features

**Explorer**
- Fuzzy search over table names, and over column names (find every table that has a `sync_status` column).
- Tables and views with live row counts, SQLite version, Drift schema version (`user_version`), size and journal mode.

**Data grid**
- Pinned header and row numbers, lazy rendering in both directions, so large tables stay smooth.
- Click a header to sort, drag a header edge to resize (double-click to auto-size).
- Global search across every column, plus a filter builder: `=`, `≠`, `>`, `≥`, `<`, `≤`, contains,
  does not contain, starts with, ends with, in list, is null, is not null.
- Right-click (or long-press) a cell to copy it, copy the row, or filter by that value.
- Paging with selectable page size, and "Open as SQL" to continue in the console.

**Row inspector**
- Every field, untruncated. JSON is pretty-printed, blobs are hex-dumped, and Unix/ISO timestamps
  get a readable local time.
- Follow a foreign key to the referenced row in one tap.
- Copy as JSON or as an `INSERT` statement; edit or delete when writes are enabled.

**Structure**
- Columns with types, PK / NOT NULL / FK badges and defaults, indexes, foreign keys, triggers and the
  original `CREATE` statement.
- One-click "Find NULLs in every column" data-quality query.

**SQL console**
- Syntax highlighting and IDE-style autocomplete for tables, columns (alias-aware: `o.` lists the
  columns of `orders o`), keywords and functions.
- Snippet library: built-in templates (browse, latest rows, value distribution, duplicates, NULLs,
  schema, integrity checks), **your app's own preset queries**, and queries users save.
- History, multi-statement scripts, run selection only, results grid with export.
- **Read-only by default.** Writes need `allowWrites: true` and are confirmed before anything runs.

**Export**: CSV, JSON, Markdown table or `INSERT` statements, to the clipboard.

Light and dark themes follow your app, and the layout adapts from desktop to phone.

## Install

```yaml
dependencies:
  drift_studio: ^0.1.0
```

## Usage

```dart
import 'package:drift_studio/drift_studio.dart';

// Push it from anywhere, e.g. a debug menu:
DriftStudio.open(context, appDatabase);

// Or embed it as a widget:
Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => DriftStudio(database: appDatabase),
));
```

Drift Studio runs every query on your database's own connection, so it sees exactly what your
app sees. After a write from the studio, Drift's stream queries are notified, so your UI updates
too.

### Configuration

```dart
DriftStudio(
  database: appDatabase,
  config: DriftStudioConfig(
    title: 'POS database',
    allowWrites: kDebugMode,      // read-only unless you opt in
    confirmWrites: true,          // ask before every write
    pageSize: 100,
    showInternalTables: false,    // hide sqlite_* tables
    queryStore: myQueryStore,     // persist saved queries + history
    presetQueries: const [
      SavedQuery(
        id: 'unsynced',
        group: 'Sync',
        title: 'Unsynced orders',
        description: 'Orders still waiting in the outbox',
        sql: "SELECT * FROM orders WHERE sync_status != 'synced';",
      ),
      SavedQuery(
        id: 'distribution',
        group: 'Sync',
        title: 'Rows per value',
        // {{table}} and {{column}} are filled from the table selected in the explorer.
        sql: 'SELECT {{column}}, COUNT(*) FROM {{table}} GROUP BY 1 ORDER BY 2 DESC;',
      ),
    ],
  ),
);
```

### Persisting saved queries

Saved queries and history are kept in memory by default. Implement `QueryStore` to keep them
across restarts, for example with `shared_preferences`:

```dart
class PrefsQueryStore implements QueryStore {
  PrefsQueryStore(this.prefs);
  final SharedPreferences prefs;

  @override
  Future<List<SavedQuery>> loadSaved() async => [
        for (final s in prefs.getStringList('studio.saved') ?? const <String>[])
          SavedQuery.fromJson(jsonDecode(s) as Map<String, Object?>),
      ];

  @override
  Future<void> writeSaved(List<SavedQuery> q) => prefs.setStringList(
      'studio.saved', [for (final s in q) jsonEncode(s.toJson())]);

  @override
  Future<List<String>> loadHistory() async =>
      prefs.getStringList('studio.history') ?? const [];

  @override
  Future<void> writeHistory(List<String> h) =>
      prefs.setStringList('studio.history', h);
}
```

### Other SQLite libraries

The studio only needs three methods, so it can sit on top of `sqflite`, `sqlite3` or anything
else that speaks SQLite:

```dart
class SqfliteSource extends StudioDataSource {
  SqfliteSource(this.db);
  final Database db;

  @override
  String get name => 'app.db';

  @override
  Future<QueryResult> select(String sql, [List<Object?> args = const []]) async {
    final watch = Stopwatch()..start();
    final rows = await db.rawQuery(sql, args);
    return QueryResult.fromMaps(rows, elapsed: watch.elapsed);
  }

  @override
  Future<int> execute(String sql, [List<Object?> args = const []]) =>
      db.rawUpdate(sql, args);
}

DriftStudio.withSource(source: SqfliteSource(db));
```

## Keyboard shortcuts (SQL console)

| Shortcut | Action |
|---|---|
| Ctrl/⌘ + Enter | Run the selection, or the whole editor |
| Ctrl + Space | Show suggestions |
| ↑ / ↓ | Move through suggestions |
| Enter / Tab | Accept suggestion |
| Esc | Dismiss suggestions |
| Tab | Indent |

## Safety notes

- **Ship it behind a debug flag or a permission.** The studio exposes your whole database.
- Read-only mode is enforced by statement classification (`SELECT`, `WITH … SELECT`, `EXPLAIN`,
  read-only `PRAGMA`s). It protects against mistakes, not against a determined user. Keep
  `allowWrites` off in production builds.
- Editing and deleting from the grid target rows by primary key, so they are only offered for tables
  that have one.

## Known limitations

- Drift returns rows as maps, so a console result with **duplicate column names** (for example
  `SELECT * FROM a JOIN b` where both have `id`) shows only one of them. Alias the columns
  (`a.id AS a_id`).
- Column widths are estimated from the first rows of each page; drag to adjust.

## Example

`example/` contains a demo app with a seeded point-of-sale database:

```bash
cd example
flutter run -d macos
```

## License

MIT
