import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../../core/query_result.dart';
import '../../core/schema.dart';
import '../../core/table_query.dart';
import '../studio_theme.dart';
import 'cell_value.dart';

/// Called for a cell context action (right-click / long-press).
typedef CellMenuCallback = void Function(
  int row,
  int column,
  Offset globalPosition,
);

/// A spreadsheet-style grid with a pinned header and row-number column,
/// lazy 2D rendering, sortable headers and draggable column widths.
class StudioDataGrid extends StatefulWidget {
  /// Creates a grid over [result].
  const StudioDataGrid({
    super.key,
    required this.result,
    this.columnInfo = const {},
    this.sortColumn,
    this.sortDirection = SortDirection.ascending,
    this.onSort,
    this.onRowTap,
    this.onCellMenu,
    this.rowNumberOffset = 0,
  });

  /// Rows and columns to show.
  final QueryResult result;

  /// Optional schema metadata keyed by column name (types, primary keys).
  final Map<String, ColumnInfo> columnInfo;

  /// Currently sorted column, for the header indicator.
  final String? sortColumn;

  /// Direction of [sortColumn].
  final SortDirection sortDirection;

  /// Header tap handler; `null` disables sorting.
  final ValueChanged<String>? onSort;

  /// Row tap handler (row index within [result]).
  final ValueChanged<int>? onRowTap;

  /// Cell context-menu handler.
  final CellMenuCallback? onCellMenu;

  /// Added to row numbers so paging shows absolute positions.
  final int rowNumberOffset;

  @override
  State<StudioDataGrid> createState() => _StudioDataGridState();
}

class _StudioDataGridState extends State<StudioDataGrid> {
  static const _rowHeight = 32.0;
  static const _headerHeight = 44.0;
  static const _minWidth = 64.0;

  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  // Column widths are view-only state: they survive page changes but are
  // recalculated when a different set of columns arrives.
  final Map<String, double> _widths = {};
  List<String> _measuredColumns = const [];
  int? _selectedRow;

  @override
  void didUpdateWidget(StudioDataGrid old) {
    super.didUpdateWidget(old);
    if (!identical(old.result, widget.result)) _selectedRow = null;
  }

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  void _ensureWidths() {
    final cols = widget.result.columns;
    if (_listEquals(cols, _measuredColumns) && _widths.isNotEmpty) return;
    _measuredColumns = cols;
    final rows = widget.result.rows.take(60);
    for (var c = 0; c < cols.length; c++) {
      final name = cols[c];
      if (_widths.containsKey(name)) continue;
      var longest = name.length + 4.0;
      final type = widget.columnInfo[name]?.declaredType ?? '';
      longest = math.max(longest, type.length + 3.0);
      for (final r in rows) {
        final len = ValueFormat.preview(r[c]).length.toDouble();
        if (len > longest) longest = len;
      }
      _widths[name] = (longest * 7.6 + 28).clamp(_minWidth + 16, 340.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    _ensureWidths();
    final result = widget.result;
    final scheme = Theme.of(context).colorScheme;
    final rowNumberWidth = math.max(48.0,
        '${widget.rowNumberOffset + result.rows.length}'.length * 9.0 + 24);
    final gridLine =
        BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45));

    return Scrollbar(
      controller: _vertical,
      thumbVisibility: true,
      child: Scrollbar(
        controller: _horizontal,
        thumbVisibility: true,
        notificationPredicate: (n) => n.depth == 1,
        child: TableView.builder(
          verticalDetails: ScrollableDetails.vertical(controller: _vertical),
          horizontalDetails:
              ScrollableDetails.horizontal(controller: _horizontal),
          diagonalDragBehavior: DiagonalDragBehavior.free,
          pinnedRowCount: 1,
          pinnedColumnCount: 1,
          rowCount: result.rows.length + 1,
          columnCount: result.columns.length + 1,
          columnBuilder: (i) => TableSpan(
            extent: FixedTableSpanExtent(
              i == 0 ? rowNumberWidth : _widths[result.columns[i - 1]] ?? 120,
            ),
            foregroundDecoration: TableSpanDecoration(
              border: TableSpanBorder(trailing: gridLine),
            ),
          ),
          rowBuilder: (i) => TableSpan(
            extent: FixedTableSpanExtent(i == 0 ? _headerHeight : _rowHeight),
            backgroundDecoration: TableSpanDecoration(
              color: i == 0
                  ? scheme.surfaceContainerHigh
                  : i - 1 == _selectedRow
                      ? scheme.primaryContainer.withValues(alpha: 0.55)
                      : i.isEven
                          ? scheme.surfaceContainerLow
                          : scheme.surface,
              border: TableSpanBorder(
                trailing: i == 0
                    ? BorderSide(color: scheme.outlineVariant)
                    : gridLine,
              ),
            ),
            cursor: i == 0 ? MouseCursor.defer : SystemMouseCursors.click,
          ),
          cellBuilder: (context, v) => TableViewCell(child: _cell(context, v)),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, TableVicinity v) {
    final result = widget.result;
    if (v.row == 0 && v.column == 0) return const SizedBox.shrink();
    if (v.row == 0) return _header(context, result.columns[v.column - 1]);
    final row = v.row - 1;
    if (v.column == 0) {
      return _RowNumber(
        number: widget.rowNumberOffset + row + 1,
        onTap: () => _tapRow(row),
      );
    }
    final column = v.column - 1;
    final info = widget.columnInfo[result.columns[column]];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tapRow(row),
      onSecondaryTapUp: (d) => _menu(row, column, d.globalPosition),
      onLongPressStart: (d) => _menu(row, column, d.globalPosition),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: CellValue(
          result.rows[row][column],
          numericColumn: info?.affinity.isNumeric ?? false,
        ),
      ),
    );
  }

  void _tapRow(int row) {
    setState(() => _selectedRow = row);
    widget.onRowTap?.call(row);
  }

  void _menu(int row, int column, Offset position) {
    setState(() => _selectedRow = row);
    widget.onCellMenu?.call(row, column, position);
  }

  Widget _header(BuildContext context, String name) {
    final info = widget.columnInfo[name];
    final sorted = widget.sortColumn == name;
    return _HeaderCell(
      name: name,
      type: info?.declaredType,
      isPrimaryKey: info?.isPrimaryKey ?? false,
      notNull: info?.notNull ?? false,
      sort: sorted ? widget.sortDirection : null,
      onTap: widget.onSort == null ? null : () => widget.onSort!(name),
      onResize: (dx) => setState(() {
        _widths[name] = math.max(_minWidth, (_widths[name] ?? 120) + dx);
      }),
      onAutoSize: () => setState(() {
        _widths.remove(name);
        _measuredColumns = const [];
      }),
    );
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _RowNumber extends StatelessWidget {
  const _RowNumber({required this.number, required this.onTap});

  final int number;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ColoredBox(
        color: scheme.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$number',
              style: monoStyle(
                context,
                size: 11,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.name,
    required this.type,
    required this.isPrimaryKey,
    required this.notNull,
    required this.sort,
    required this.onTap,
    required this.onResize,
    required this.onAutoSize,
  });

  final String name;
  final String? type;
  final bool isPrimaryKey;
  final bool notNull;
  final SortDirection? sort;
  final VoidCallback? onTap;
  final ValueChanged<double> onResize;
  final VoidCallback onAutoSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Stack(
      children: [
        Positioned.fill(
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 14, 4),
              child: Row(
                children: [
                  if (isPrimaryKey)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(Icons.key_rounded,
                          size: 13, color: scheme.primary),
                    ),
                  Expanded(child: _labels(theme)),
                  if (sort != null)
                    Icon(
                      sort == SortDirection.ascending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                      size: 14,
                      color: scheme.primary,
                    ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          width: 8,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => onResize(d.delta.dx),
              onDoubleTap: onAutoSize,
            ),
          ),
        ),
      ],
    );
  }

  Widget _labels(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
        if (type != null)
          Text(
            [
              if (type!.isNotEmpty) type!.toLowerCase() else 'any',
              if (notNull) 'not null'
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}
