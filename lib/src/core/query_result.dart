/// The tabular outcome of running a SQL statement.
class QueryResult {
  /// Creates a result with explicit [columns] and positional [rows].
  const QueryResult({
    required this.columns,
    required this.rows,
    this.elapsed = Duration.zero,
    this.affectedRows,
  });

  /// Builds a result from map-shaped rows, as returned by most SQLite APIs.
  ///
  /// Column order follows the first row; later rows are aligned to it so a
  /// grid can render positionally without repeated map lookups.
  factory QueryResult.fromMaps(
    List<Map<String, Object?>> maps, {
    Duration elapsed = Duration.zero,
    List<String>? fallbackColumns,
  }) {
    final columns =
        maps.isEmpty ? (fallbackColumns ?? const []) : maps.first.keys.toList();
    final rows = [
      for (final map in maps) [for (final c in columns) map[c]],
    ];
    return QueryResult(columns: columns, rows: rows, elapsed: elapsed);
  }

  /// An empty result, used before anything has run.
  static const empty = QueryResult(columns: [], rows: []);

  /// Column names in result order.
  final List<String> columns;

  /// Row values, each aligned with [columns].
  final List<List<Object?>> rows;

  /// Wall-clock time spent executing the statement.
  final Duration elapsed;

  /// Rows changed by a write statement; `null` for reads.
  final int? affectedRows;

  /// Whether this result came from a write statement.
  bool get isWrite => affectedRows != null;

  /// Returns row [index] as a column→value map.
  Map<String, Object?> rowAsMap(int index) =>
      {for (var i = 0; i < columns.length; i++) columns[i]: rows[index][i]};
}
