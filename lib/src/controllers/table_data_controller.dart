import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/query_result.dart';
import '../core/schema.dart';
import '../core/sql_utils.dart';
import '../core/studio_data_source.dart';
import '../core/table_query.dart';

/// State for one table's data grid: paging, sorting, search and filters.
///
/// One controller is kept per table, so switching tables and coming back
/// restores the exact view the user left.
class TableDataController extends ChangeNotifier {
  /// Creates a controller for [details] and loads the first page.
  TableDataController({
    required this.source,
    required this.details,
    required int pageSize,
    required this.allowWrites,
  }) : _query = TableQuery(
          table: details.object.name,
          columns: [for (final c in details.columns) c.name],
          limit: pageSize,
        ) {
    unawaited(reload());
  }

  /// The database.
  final StudioDataSource source;

  /// Structure of the table being browsed.
  final TableDetails details;

  /// Whether editing and deleting rows is permitted.
  final bool allowWrites;

  TableQuery _query;
  QueryResult _result = QueryResult.empty;
  int? _totalRows;
  bool _loading = false;
  Object? _error;
  int _generation = 0;
  bool _disposed = false;

  /// The current query description.
  TableQuery get query => _query;

  /// The current page of rows.
  QueryResult get result => _result;

  /// Rows matching the current search/filters, once counted.
  int? get totalRows => _totalRows;

  /// Whether a page is loading.
  bool get loading => _loading;

  /// The last load error, if any.
  Object? get error => _error;

  /// Zero-based page index.
  int get page => _query.offset ~/ _query.limit;

  /// Number of pages, once counted.
  int? get pageCount => _totalRows == null
      ? null
      : (_totalRows! / _query.limit).ceil().clamp(1, 1 << 31);

  /// Whether rows can be edited: writes allowed, a real table, and a primary
  /// key to target the row precisely.
  bool get canEdit =>
      allowWrites &&
      details.object.type == DbObjectType.table &&
      details.primaryKey.isNotEmpty;

  /// Reloads the current page and the matching-row count.
  Future<void> reload() async {
    // A generation counter drops results of superseded requests, so fast
    // typing in the search box never shows a stale page.
    final gen = ++_generation;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final select = _query.selectSql();
      final count = _query.countSql();
      final page = await source.select(select.sql, select.args);
      final total = await source.select(count.sql, count.args);
      if (gen != _generation) return;
      // An empty page carries no column names, so fall back to the schema.
      _result = page.rows.isEmpty
          ? QueryResult(
              columns: _query.columns,
              rows: const [],
              elapsed: page.elapsed,
            )
          : page;
      _totalRows = (total.rows.first.first as num?)?.toInt();
    } catch (e) {
      if (gen != _generation) return;
      _error = e;
      _result = QueryResult(columns: _query.columns, rows: const []);
    } finally {
      if (gen == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Sets the global search text and returns to the first page.
  Future<void> setSearch(String text) {
    if (text == _query.search) return Future.value();
    _query = _query.copyWith(search: text, offset: 0);
    return reload();
  }

  /// Adds or replaces a column filter.
  Future<void> addFilter(ColumnFilter filter, {int? replaceAt}) {
    final next = List.of(_query.filters);
    if (replaceAt != null && replaceAt < next.length) {
      next[replaceAt] = filter;
    } else {
      next.add(filter);
    }
    _query = _query.copyWith(filters: next, offset: 0);
    return reload();
  }

  /// Removes the filter at [index].
  Future<void> removeFilter(int index) {
    final next = List.of(_query.filters)..removeAt(index);
    _query = _query.copyWith(filters: next, offset: 0);
    return reload();
  }

  /// Removes every column filter.
  Future<void> clearFilters() {
    _query = _query.copyWith(filters: const [], offset: 0);
    return reload();
  }

  /// Clears search, filters and sorting.
  Future<void> resetView() {
    _query = _query.copyWith(
      search: '',
      filters: const [],
      sortColumn: () => null,
      offset: 0,
    );
    return reload();
  }

  /// Cycles a column through ascending → descending → unsorted.
  Future<void> toggleSort(String column) {
    if (_query.sortColumn != column) {
      _query = _query.copyWith(
        sortColumn: () => column,
        sortDirection: SortDirection.ascending,
      );
    } else if (_query.sortDirection == SortDirection.ascending) {
      _query = _query.copyWith(sortDirection: SortDirection.descending);
    } else {
      _query = _query.copyWith(sortColumn: () => null);
    }
    _query = _query.copyWith(offset: 0);
    return reload();
  }

  /// Jumps to page [index] (zero-based).
  Future<void> goToPage(int index) {
    final max = (pageCount ?? 1) - 1;
    final target = index.clamp(0, max < 0 ? 0 : max);
    _query = _query.copyWith(offset: target * _query.limit);
    return reload();
  }

  /// Changes the page size, keeping the first visible row on screen.
  Future<void> setPageSize(int size) {
    final firstRow = _query.offset;
    _query = _query.copyWith(limit: size, offset: (firstRow ~/ size) * size);
    return reload();
  }

  /// Updates one cell of row [rowIndex], targeting it by primary key.
  Future<void> updateCell(int rowIndex, String column, Object? value) async {
    _assertEditable();
    final where = _primaryKeyWhere(rowIndex);
    await source.execute(
      'UPDATE ${SqlUtils.quote(details.object.name)} '
      'SET ${SqlUtils.quote(column)} = ? WHERE ${where.sql}',
      [value, ...where.args],
    );
    await source.onDataChanged();
    await reload();
  }

  /// Deletes row [rowIndex], targeting it by primary key.
  Future<void> deleteRow(int rowIndex) async {
    _assertEditable();
    final where = _primaryKeyWhere(rowIndex);
    await source.execute(
      'DELETE FROM ${SqlUtils.quote(details.object.name)} WHERE ${where.sql}',
      where.args,
    );
    await source.onDataChanged();
    await reload();
  }

  void _assertEditable() {
    if (!canEdit) {
      throw StateError(
        'Editing needs allowWrites and a table with a primary key.',
      );
    }
  }

  BoundSql _primaryKeyWhere(int rowIndex) {
    final row = _result.rowAsMap(rowIndex);
    final pk = details.primaryKey;
    return (
      sql: pk.map((c) => '${SqlUtils.quote(c.name)} = ?').join(' AND '),
      args: [for (final c in pk) row[c.name]],
    );
  }
}
