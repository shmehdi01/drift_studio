import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/schema.dart';
import '../core/schema_inspector.dart';
import '../core/sql_autocomplete.dart';
import '../core/table_query.dart';
import '../core/studio_data_source.dart';
import '../drift_studio_config.dart';
import 'sql_console_controller.dart';
import 'table_data_controller.dart';

/// The main panes of the studio.
enum StudioPane {
  /// Rows of the selected table.
  data,

  /// Columns, indexes, keys and DDL of the selected table.
  structure,

  /// Free-form SQL console.
  console,
}

/// Root state of the studio: the object catalog, the current selection and
/// the per-table controllers.
class StudioController extends ChangeNotifier {
  /// Creates the controller and starts loading the catalog.
  StudioController({required this.source, required this.config})
      : inspector = SchemaInspector(source) {
    console = SqlConsoleController(
      source: source,
      config: config,
      onWrite: _afterConsoleWrite,
    );
    unawaited(load());
  }

  /// The database.
  final StudioDataSource source;

  /// Studio options.
  final DriftStudioConfig config;

  /// Catalog reader.
  final SchemaInspector inspector;

  /// The SQL console state, shared across table selections.
  late final SqlConsoleController console;

  List<DbObject> _objects = const [];
  final Map<String, int> _rowCounts = {};
  final Map<String, TableDetails> _details = {};
  final Map<String, TableDataController> _tables = {};
  Map<String, List<(String, String)>> _columnIndex = const {};
  DatabaseInfo? _info;
  DbObject? _selected;
  StudioPane _pane = StudioPane.data;
  String _sidebarFilter = '';
  bool _loading = true;
  Object? _error;
  bool _disposed = false;

  /// Every `sqlite_master` entry.
  List<DbObject> get objects => _objects;

  /// Database-level info, once loaded.
  DatabaseInfo? get info => _info;

  /// The selected table or view.
  DbObject? get selected => _selected;

  /// The visible pane.
  StudioPane get pane => _pane;

  /// Sidebar search text.
  String get sidebarFilter => _sidebarFilter;

  /// Whether the catalog is loading.
  bool get loading => _loading;

  /// Catalog load error, if any.
  Object? get error => _error;

  /// Cached row count for [table], if counted.
  int? rowCount(String table) => _rowCounts[table];

  /// The column `{{column}}` placeholders resolve to for [table]: the first
  /// one that isn't a surrogate `id`, since grouping by a key is pointless.
  String? templateColumnOf(String table) {
    final cols = _columnIndex[table];
    if (cols == null || cols.isEmpty) return null;
    for (final (name, _) in cols) {
      if (name.toLowerCase() != 'id') return name;
    }
    return cols.first.$1;
  }

  /// Autocomplete over every table and view.
  SqlAutocomplete get autocomplete => SqlAutocomplete(_columnIndex);

  /// Objects of [type] matching the sidebar filter, best matches first.
  ///
  /// Ranking: name contains the text, then a fuzzy subsequence match (so
  /// `ordit` finds `order_item`), then tables that only match by a column
  /// name — searching for a column surfaces the tables that hold it.
  List<DbObject> visibleObjects(DbObjectType type) {
    final f = _sidebarFilter.trim().toLowerCase();
    final candidates = [
      for (final o in _objects)
        if (o.type == type && (config.showInternalTables || !o.isInternal)) o,
    ];
    if (f.isEmpty) return candidates;
    final direct = <DbObject>[];
    final fuzzy = <DbObject>[];
    final byColumn = <DbObject>[];
    for (final o in candidates) {
      final name = o.name.toLowerCase();
      if (name.contains(f)) {
        direct.add(o);
      } else if (f.length >= 3 && _fuzzy(name, f)) {
        fuzzy.add(o);
      } else if (matchingColumns(o.name).isNotEmpty) {
        byColumn.add(o);
      }
    }
    return [...direct, ...fuzzy, ...byColumn];
  }

  /// Column names of [table] matching the sidebar filter, so searching for a
  /// column surfaces the tables that contain it.
  List<String> matchingColumns(String table) {
    final f = _sidebarFilter.trim().toLowerCase();
    if (f.length < 2) return const [];
    return [
      for (final (c, _) in _columnIndex[table] ?? const <(String, String)>[])
        if (c.toLowerCase().contains(f)) c,
    ];
  }

  /// (Re)loads the catalog, database info and column index.
  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _objects = await inspector.listObjects();
      _info = await inspector.databaseInfo();
      _columnIndex = await _loadColumnIndex();
      _details.clear();
      for (final t in _tables.values) {
        t.dispose();
      }
      _tables.clear();
      if (_selected != null) {
        _selected =
            _objects.where((o) => o.name == _selected!.name).firstOrNull;
      }
      _selected ??= visibleObjects(DbObjectType.table).firstOrNull ??
          visibleObjects(DbObjectType.view).firstOrNull;
    } catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
    unawaited(_countRows());
  }

  /// Selects [object] and shows its data (or keeps the current pane).
  void select(DbObject object, {StudioPane? pane}) {
    _selected = object;
    if (pane != null) {
      _pane = pane;
    } else if (_pane == StudioPane.console) {
      _pane = StudioPane.data;
    }
    notifyListeners();
  }

  /// Switches the visible pane.
  void showPane(StudioPane pane) {
    if (_pane == pane) return;
    _pane = pane;
    notifyListeners();
  }

  /// Updates the sidebar search text.
  void setSidebarFilter(String value) {
    _sidebarFilter = value;
    notifyListeners();
  }

  /// Loads (and caches) the structure of [object].
  Future<TableDetails> details(DbObject object) async {
    final cached = _details[object.name];
    if (cached != null) return cached;
    final d = await inspector.describe(object, _objects);
    return _details[object.name] = d;
  }

  /// Returns the cached grid controller for [details], creating it lazily.
  TableDataController tableController(TableDetails details) =>
      _tables.putIfAbsent(
        details.object.name,
        () => TableDataController(
          source: source,
          details: details,
          pageSize: config.pageSize,
          allowWrites: config.allowWrites,
        ),
      );

  /// Jumps to [table] showing only rows matching [filter] — used to follow
  /// a foreign key from the row inspector.
  Future<void> openFiltered(String table, ColumnFilter filter) async {
    final target = _objects.where((o) => o.name == table).firstOrNull;
    if (target == null) return;
    select(target, pane: StudioPane.data);
    final grid = tableController(await details(target));
    await grid.resetView();
    await grid.addFilter(filter);
  }

  /// Opens [sql] in the console, for "open as SQL" actions.
  void openInConsole(String sql) {
    console.load(sql);
    _pane = StudioPane.console;
    notifyListeners();
  }

  Future<Map<String, List<(String, String)>>> _loadColumnIndex() async {
    // One round trip via the table-valued pragma instead of one per table.
    final r = await source.select(
      // Aliases matter: rows arrive as maps, so two `name` columns would
      // collapse into one.
      'SELECT m.name AS table_name, p.name AS column_name, '
      'p.type AS column_type FROM sqlite_master m '
      'JOIN pragma_table_info(m.name) p '
      "WHERE m.type IN ('table', 'view') ORDER BY m.name, p.cid",
    );
    final out = <String, List<(String, String)>>{};
    for (final row in r.rows) {
      (out[row[0]! as String] ??= [])
          .add((row[1]! as String, '${row[2] ?? ''}'));
    }
    return out;
  }

  /// Counts rows table by table so the sidebar fills in progressively without
  /// one slow table blocking the rest.
  Future<void> _countRows() async {
    for (final o in _objects.where((o) => o.type == DbObjectType.table)) {
      if (_disposed) return;
      try {
        _rowCounts[o.name] = await inspector.countRows(o.name);
        notifyListeners();
      } catch (_) {
        // Counting is best-effort; virtual tables may refuse COUNT(*).
      }
    }
  }

  Future<void> _afterConsoleWrite({required bool schemaChanged}) async {
    if (schemaChanged) {
      await load();
    } else {
      _rowCounts.clear();
      for (final t in _tables.values) {
        unawaited(t.reload());
      }
      unawaited(_countRows());
    }
  }

  static bool _fuzzy(String text, String pattern) {
    var i = 0;
    for (var j = 0; j < text.length && i < pattern.length; j++) {
      if (text[j] == pattern[i]) i++;
    }
    return i == pattern.length;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final t in _tables.values) {
      t.dispose();
    }
    console.dispose();
    super.dispose();
  }
}
