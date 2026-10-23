import 'sql_utils.dart';

/// Comparison operators available in the table filter builder.
enum FilterOperator {
  /// `=`
  equals('=', 'equals'),

  /// `!=`
  notEquals('≠', 'not equals'),

  /// `>`
  greaterThan('>', 'greater than'),

  /// `>=`
  greaterOrEqual('≥', 'greater or equal'),

  /// `<`
  lessThan('<', 'less than'),

  /// `<=`
  lessOrEqual('≤', 'less or equal'),

  /// Case-insensitive substring match.
  contains('∋', 'contains'),

  /// Negated case-insensitive substring match.
  notContains('∌', 'does not contain'),

  /// Case-insensitive prefix match.
  startsWith('a…', 'starts with'),

  /// Case-insensitive suffix match.
  endsWith('…a', 'ends with'),

  /// Comma-separated list membership.
  inList('in', 'in list'),

  /// `IS NULL`
  isNull('∅', 'is null'),

  /// `IS NOT NULL`
  isNotNull('≠∅', 'is not null');

  const FilterOperator(this.symbol, this.label);

  /// Compact symbol for chips.
  final String symbol;

  /// Readable label for menus.
  final String label;

  /// Whether the operator needs a user-entered value.
  bool get needsValue => this != isNull && this != isNotNull;
}

/// One column condition applied to the data grid.
class ColumnFilter {
  /// Creates a filter on [column].
  const ColumnFilter({
    required this.column,
    required this.operator,
    this.value = '',
  });

  /// Column the condition applies to.
  final String column;

  /// Comparison operator.
  final FilterOperator operator;

  /// Raw user input; numbers are detected automatically.
  final String value;

  /// Appends this condition's SQL to [where] and its bound values to [args].
  void writeTo(List<String> where, List<Object?> args) {
    final col = SqlUtils.quote(column);
    String like(String pattern) {
      args.add(pattern);
      return "$col LIKE ? ESCAPE '\\'";
    }

    final escaped = SqlUtils.escapeLike(value);
    switch (operator) {
      case FilterOperator.isNull:
        where.add('$col IS NULL');
      case FilterOperator.isNotNull:
        where.add('$col IS NOT NULL');
      case FilterOperator.contains:
        where.add(like('%$escaped%'));
      case FilterOperator.notContains:
        where.add('NOT (${like('%$escaped%')})');
      case FilterOperator.startsWith:
        where.add(like('$escaped%'));
      case FilterOperator.endsWith:
        where.add(like('%$escaped'));
      case FilterOperator.inList:
        final items = value
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (items.isEmpty) {
          where.add('0');
        } else {
          where.add('$col IN (${List.filled(items.length, '?').join(', ')})');
          args.addAll(items.map(_coerce));
        }
      case FilterOperator.equals:
      case FilterOperator.notEquals:
      case FilterOperator.greaterThan:
      case FilterOperator.greaterOrEqual:
      case FilterOperator.lessThan:
      case FilterOperator.lessOrEqual:
        where.add('$col ${_sqlOperator(operator)} ?');
        args.add(_coerce(value));
    }
  }

  /// Bound parameters have no affinity, so a numeric string is passed as a
  /// number to make comparisons against untyped view columns behave.
  static Object _coerce(String raw) => num.tryParse(raw.trim()) ?? raw;

  static String _sqlOperator(FilterOperator op) => switch (op) {
        FilterOperator.notEquals => '!=',
        FilterOperator.greaterThan => '>',
        FilterOperator.greaterOrEqual => '>=',
        FilterOperator.lessThan => '<',
        FilterOperator.lessOrEqual => '<=',
        _ => '=',
      };
}

/// Sort direction for a grid column.
enum SortDirection {
  /// Ascending.
  ascending,

  /// Descending.
  descending,
}

/// A built SQL statement with its bound arguments.
typedef BoundSql = ({String sql, List<Object?> args});

/// Builds the paged, filtered, sorted `SELECT` used by the data grid.
class TableQuery {
  /// Creates a query description.
  const TableQuery({
    required this.table,
    required this.columns,
    this.search = '',
    this.filters = const [],
    this.sortColumn,
    this.sortDirection = SortDirection.ascending,
    this.limit = 100,
    this.offset = 0,
  });

  /// Table or view name.
  final String table;

  /// All columns, used for the global search across every column.
  final List<String> columns;

  /// Free-text search applied to every column with `LIKE`.
  final String search;

  /// Column conditions, combined with `AND`.
  final List<ColumnFilter> filters;

  /// Column to sort by, or `null` for natural order.
  final String? sortColumn;

  /// Direction for [sortColumn].
  final SortDirection sortDirection;

  /// Page size.
  final int limit;

  /// Rows to skip.
  final int offset;

  /// The `WHERE` clause (without the keyword) and its arguments.
  BoundSql whereClause() {
    final where = <String>[];
    final args = <Object?>[];
    final term = search.trim();
    if (term.isNotEmpty && columns.isNotEmpty) {
      final pattern = '%${SqlUtils.escapeLike(term)}%';
      where.add('(${columns.map((c) {
        args.add(pattern);
        return "CAST(${SqlUtils.quote(c)} AS TEXT) LIKE ? ESCAPE '\\'";
      }).join(' OR ')})');
    }
    for (final f in filters) {
      f.writeTo(where, args);
    }
    return (sql: where.join(' AND '), args: args);
  }

  /// The page `SELECT`.
  BoundSql selectSql() {
    final w = whereClause();
    final b = StringBuffer('SELECT * FROM ${SqlUtils.quote(table)}');
    if (w.sql.isNotEmpty) b.write(' WHERE ${w.sql}');
    if (sortColumn != null) {
      b.write(' ORDER BY ${SqlUtils.quote(sortColumn!)} '
          '${sortDirection == SortDirection.ascending ? 'ASC' : 'DESC'}');
    }
    b.write(' LIMIT $limit OFFSET $offset');
    return (sql: b.toString(), args: w.args);
  }

  /// The matching-row `COUNT(*)`.
  BoundSql countSql() {
    final w = whereClause();
    final b = StringBuffer('SELECT COUNT(*) FROM ${SqlUtils.quote(table)}');
    if (w.sql.isNotEmpty) b.write(' WHERE ${w.sql}');
    return (sql: b.toString(), args: w.args);
  }

  /// A readable, copy-pasteable version of [selectSql] with literals inlined
  /// and no paging, for "open in SQL console".
  String toInlineSql() {
    final s = selectSql();
    var i = 0;
    final inlined = s.sql.replaceAllMapped(RegExp(r'\?'), (_) {
      final v = s.args[i++];
      if (v is num) return '$v';
      if (v == null) return 'NULL';
      return "'${v.toString().replaceAll("'", "''")}'";
    });
    return inlined.replaceFirst(
        RegExp(r' LIMIT \d+ OFFSET \d+$'), ' LIMIT $limit');
  }

  /// Returns a copy with the given fields replaced.
  TableQuery copyWith({
    String? search,
    List<ColumnFilter>? filters,
    String? Function()? sortColumn,
    SortDirection? sortDirection,
    int? limit,
    int? offset,
  }) =>
      TableQuery(
        table: table,
        columns: columns,
        search: search ?? this.search,
        filters: filters ?? this.filters,
        sortColumn: sortColumn != null ? sortColumn() : this.sortColumn,
        sortDirection: sortDirection ?? this.sortDirection,
        limit: limit ?? this.limit,
        offset: offset ?? this.offset,
      );
}
