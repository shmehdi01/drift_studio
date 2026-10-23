import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/query_result.dart';
import '../core/saved_query.dart';
import '../core/sql_utils.dart';
import '../core/studio_data_source.dart';
import '../drift_studio_config.dart';
import 'sql_editing_controller.dart';

/// Asks the user to approve write statements before they run.
typedef WriteConfirmation = Future<bool> Function(List<String> statements);

/// Notifies the studio that a console write changed data or schema.
typedef ConsoleWriteCallback = Future<void> Function({
  required bool schemaChanged,
});

/// Thrown when a write is attempted while writes are disabled.
class WritesDisabledException implements Exception {
  /// Creates the exception for [statement].
  const WritesDisabledException(this.statement);

  /// The rejected statement.
  final String statement;

  @override
  String toString() => 'Read-only mode: this statement modifies the database.\n'
      'Pass DriftStudioConfig(allowWrites: true) to enable writes.';
}

/// State for the SQL console: editor text, execution, history and snippets.
class SqlConsoleController extends ChangeNotifier {
  /// Creates the console and loads persisted queries.
  SqlConsoleController({
    required this.source,
    required this.config,
    required this.onWrite,
  }) : store = config.queryStore ?? InMemoryQueryStore() {
    unawaited(_restore());
  }

  /// The database.
  final StudioDataSource source;

  /// Studio options.
  final DriftStudioConfig config;

  /// Where saved queries and history persist.
  final QueryStore store;

  /// Called after writes so other panes can refresh.
  final ConsoleWriteCallback onWrite;

  /// The editor's text controller, with syntax highlighting.
  final SqlEditingController editor = SqlEditingController(
    text:
        '-- Write SQL here. Ctrl/⌘ + Enter runs the selection or everything.\n',
  );

  QueryResult? _result;
  Object? _error;
  bool _running = false;
  int _statementCount = 0;
  List<String> _history = [];
  List<SavedQuery> _saved = [];
  bool _disposed = false;

  /// Result of the last row-returning statement, or a write summary.
  QueryResult? get result => _result;

  /// Error from the last run.
  Object? get error => _error;

  /// Whether a run is in progress.
  bool get running => _running;

  /// Statements executed by the last run.
  int get statementCount => _statementCount;

  /// Previously run SQL, newest first.
  List<String> get history => _history;

  /// User-saved queries.
  List<SavedQuery> get saved => _saved;

  /// Every snippet offered in the side panel, grouped by [SavedQuery.group]:
  /// app presets first, then the user's saved queries, then built-ins.
  List<SavedQuery> get snippets => [
        ...config.presetQueries,
        ..._saved,
        ...BuiltInQueries.templates,
      ];

  /// The SQL that a run would execute: the selection, or the whole editor.
  String get runnableSql {
    final sel = editor.selection;
    if (sel.isValid && !sel.isCollapsed) {
      final picked = sel.textInside(editor.text);
      if (picked.trim().isNotEmpty) return picked;
    }
    return editor.text;
  }

  /// Executes [sql] (or [runnableSql]) statement by statement.
  ///
  /// Writes are rejected in read-only mode and, when configured, confirmed
  /// via [confirm] *before* anything runs so a script never half-applies
  /// because the user declined midway.
  Future<void> run({String? sql, WriteConfirmation? confirm}) async {
    if (_running) return;
    final text = sql ?? runnableSql;
    final statements = SqlUtils.splitStatements(text);
    if (statements.isEmpty) return;

    final writes = statements.where((s) => !SqlUtils.isReadOnly(s)).toList();
    if (writes.isNotEmpty && !config.allowWrites) {
      _error = WritesDisabledException(writes.first);
      _result = null;
      notifyListeners();
      return;
    }
    if (writes.isNotEmpty && config.confirmWrites && confirm != null) {
      if (!await confirm(writes)) return;
    }

    _running = true;
    _error = null;
    notifyListeners();

    final watch = Stopwatch()..start();
    QueryResult? last;
    var affected = 0;
    var executed = 0;
    var schemaChanged = false;
    try {
      for (final s in statements) {
        if (SqlUtils.returnsRows(s)) {
          last = await source.select(s);
        } else {
          affected += await source.execute(s);
          last = null;
        }
        executed++;
        schemaChanged |=
            RegExp(r'^\s*(CREATE|DROP|ALTER)\b', caseSensitive: false)
                .hasMatch(s);
      }
      watch.stop();
      _result = last != null
          ? QueryResult(
              columns: last.columns,
              rows: last.rows,
              elapsed: watch.elapsed,
              affectedRows: writes.isEmpty ? null : affected,
            )
          : QueryResult(
              columns: const [],
              rows: const [],
              elapsed: watch.elapsed,
              affectedRows: affected,
            );
    } catch (e) {
      _error = e;
      _result = null;
    } finally {
      _statementCount = executed;
      _running = false;
      notifyListeners();
    }
    await _remember(text);
    if (writes.isNotEmpty && executed > 0) {
      await source.onDataChanged();
      await onWrite(schemaChanged: schemaChanged);
    }
  }

  /// Replaces the editor content with [sql] and moves the caret to the end.
  void load(String sql) {
    editor.value = TextEditingValue(
      text: sql,
      selection: TextSelection.collapsed(offset: sql.length),
    );
  }

  /// Saves the current editor text as a named query.
  Future<void> saveCurrent(String title, {String? description}) async {
    final query = SavedQuery(
      id: 'saved.${DateTime.now().microsecondsSinceEpoch}',
      title: title,
      description: description,
      sql: editor.text.trim(),
      group: 'Saved',
    );
    _saved = [query, ..._saved];
    notifyListeners();
    await store.writeSaved(_saved);
  }

  /// Deletes a user-saved query.
  Future<void> deleteSaved(String id) async {
    _saved = _saved.where((q) => q.id != id).toList();
    notifyListeners();
    await store.writeSaved(_saved);
  }

  /// Clears the run history.
  Future<void> clearHistory() async {
    _history = [];
    notifyListeners();
    await store.writeHistory(_history);
  }

  Future<void> _remember(String sql) async {
    final s = sql.trim();
    if (s.isEmpty) return;
    _history = [s, ..._history.where((h) => h != s)]
        .take(config.historyLimit)
        .toList();
    notifyListeners();
    await store.writeHistory(_history);
  }

  Future<void> _restore() async {
    _saved = await store.loadSaved();
    _history = await store.loadHistory();
    notifyListeners();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    editor.dispose();
    super.dispose();
  }
}
