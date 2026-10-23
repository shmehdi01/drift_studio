import 'dart:async';

import 'package:flutter/material.dart';

import '../../controllers/studio_controller.dart';
import '../../controllers/table_data_controller.dart';
import '../../core/export.dart';
import '../../core/schema.dart';
import '../../core/table_query.dart';
import '../widgets/cell_value.dart';
import '../widgets/data_grid.dart';
import '../widgets/export_menu.dart';
import '../widgets/feedback.dart';
import 'filter_dialog.dart';
import 'row_inspector.dart';

/// Browses the rows of one table: search, filters, sorting, paging, export
/// and the row inspector.
class DataPane extends StatelessWidget {
  /// Creates the pane for [details].
  const DataPane({
    super.key,
    required this.studio,
    required this.details,
  });

  /// Root controller (for cross-table navigation and the console).
  final StudioController studio;

  /// Structure of the table being browsed.
  final TableDetails details;

  @override
  Widget build(BuildContext context) {
    final grid = studio.tableController(details);
    return ListenableBuilder(
      listenable: grid,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(studio: studio, grid: grid),
          if (grid.query.filters.isNotEmpty) _FilterChips(grid: grid),
          if (grid.loading)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          Expanded(child: _body(context, grid)),
          const Divider(),
          _Pagination(grid: grid),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, TableDataController grid) {
    if (grid.error != null) {
      return StudioMessage(
        icon: Icons.error_outline_rounded,
        title: 'Query failed',
        detail: '${grid.error}',
        isError: true,
      );
    }
    if (!grid.loading && grid.result.rows.isEmpty) {
      final filtered =
          grid.query.search.isNotEmpty || grid.query.filters.isNotEmpty;
      return StudioMessage(
        icon: filtered ? Icons.filter_alt_off_outlined : Icons.inbox_outlined,
        title: filtered ? 'No rows match' : 'This table is empty',
      );
    }
    return StudioDataGrid(
      result: grid.result,
      columnInfo: {for (final c in details.columns) c.name: c},
      sortColumn: grid.query.sortColumn,
      sortDirection: grid.query.sortDirection,
      onSort: grid.toggleSort,
      rowNumberOffset: grid.query.offset,
      onRowTap: (row) => _inspect(context, grid, row),
      onCellMenu: (row, col, pos) => _cellMenu(context, grid, row, col, pos),
    );
  }

  Future<void> _inspect(
      BuildContext context, TableDataController grid, int row) {
    return showRowInspector(
      context,
      result: grid.result,
      index: row,
      title: '${details.object.name} · row ${grid.query.offset + row + 1}',
      details: details,
      actions: RowInspectorActions(
        onEdit: grid.canEdit
            ? (column, value) => grid.updateCell(row, column, value)
            : null,
        onDelete: grid.canEdit ? () => grid.deleteRow(row) : null,
        onFollowForeignKey: (fk, value) => studio.openFiltered(
          fk.table,
          ColumnFilter(
            column: fk.toColumn ?? 'rowid',
            operator: FilterOperator.equals,
            value: '$value',
          ),
        ),
      ),
    );
  }

  Future<void> _cellMenu(
    BuildContext context,
    TableDataController grid,
    int row,
    int column,
    Offset position,
  ) async {
    final name = grid.result.columns[column];
    final value = grid.result.rows[row][column];
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
          position & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        const PopupMenuItem(value: 'copy', child: Text('Copy value')),
        const PopupMenuItem(value: 'row', child: Text('Copy row as JSON')),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'eq',
          child: Text(value == null
              ? 'Filter: $name is null'
              : 'Filter: $name = this value'),
        ),
        if (value != null)
          PopupMenuItem(
              value: 'neq', child: Text('Filter: $name ≠ this value')),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: 'inspect', child: Text('Open row inspector')),
      ],
    );
    if (!context.mounted || choice == null) return;
    switch (choice) {
      case 'copy':
        await copyToClipboard(
            context, value == null ? 'NULL' : ValueFormat.full(value));
      case 'row':
        await copyToClipboard(
          context,
          ResultExporter.rowToJson(grid.result.rowAsMap(row)),
          label: 'Row copied as JSON',
        );
      case 'eq':
        await grid.addFilter(value == null
            ? ColumnFilter(column: name, operator: FilterOperator.isNull)
            : ColumnFilter(
                column: name,
                operator: FilterOperator.equals,
                value: '$value'));
      case 'neq':
        await grid.addFilter(
          ColumnFilter(
              column: name,
              operator: FilterOperator.notEquals,
              value: '$value'),
        );
      case 'inspect':
        await _inspect(context, grid, row);
    }
  }
}

class _Toolbar extends StatefulWidget {
  const _Toolbar({required this.studio, required this.grid});

  final StudioController studio;
  final TableDataController grid;

  @override
  State<_Toolbar> createState() => _ToolbarState();
}

class _ToolbarState extends State<_Toolbar> {
  late final _search = TextEditingController(text: widget.grid.query.search);
  Timer? _debounce;

  @override
  void didUpdateWidget(_Toolbar old) {
    super.didUpdateWidget(old);
    if (old.grid != widget.grid ||
        widget.grid.query.search != _search.text &&
            _debounce?.isActive != true) {
      _search.text = widget.grid.query.search;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    // Every keystroke would otherwise fire two LIKE scans over the table.
    _debounce?.cancel();
    _debounce = Timer(
        const Duration(milliseconds: 280), () => widget.grid.setSearch(v));
  }

  @override
  Widget build(BuildContext context) {
    final grid = widget.grid;
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: 'Search all columns',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close_rounded, size: 16),
                        onPressed: () {
                          _search.clear();
                          _debounce?.cancel();
                          grid.setSearch('');
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (compact)
            IconButton.filledTonal(
              tooltip: 'Add filter',
              icon: const Icon(Icons.filter_alt_outlined, size: 18),
              onPressed: _addFilter,
            )
          else
            FilledButton.tonalIcon(
              onPressed: _addFilter,
              icon: const Icon(Icons.filter_alt_outlined, size: 18),
              label: const Text('Filter'),
            ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: grid.reload,
          ),
          ExportMenu(result: grid.result, tableName: grid.details.object.name),
          PopupMenuButton<String>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert_rounded, size: 20),
            onSelected: (v) {
              if (v == 'sql') {
                widget.studio.openInConsole('${grid.query.toInlineSql()};');
              }
              if (v == 'reset') {
                _search.clear();
                grid.resetView();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'sql', child: Text('Open as SQL')),
              PopupMenuItem(
                  value: 'reset', child: Text('Reset search, filters & sort')),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addFilter() async {
    final f =
        await showFilterDialog(context, columns: widget.grid.details.columns);
    if (f != null) await widget.grid.addFilter(f);
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.grid});

  final TableDataController grid;

  @override
  Widget build(BuildContext context) {
    final filters = grid.query.filters;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < filters.length; i++)
            InputChip(
              label: Text(
                filters[i].operator.needsValue
                    ? '${filters[i].column} ${filters[i].operator.label} ${filters[i].value}'
                    : '${filters[i].column} ${filters[i].operator.label}',
              ),
              onPressed: () async {
                final f = await showFilterDialog(
                  context,
                  columns: grid.details.columns,
                  initial: filters[i],
                );
                if (f != null) await grid.addFilter(f, replaceAt: i);
              },
              onDeleted: () => grid.removeFilter(i),
            ),
          if (filters.length > 1)
            ActionChip(
              label: const Text('Clear all'),
              onPressed: grid.clearFilters,
            ),
        ],
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  const _Pagination({required this.grid});

  final TableDataController grid;

  static const _sizes = [25, 50, 100, 250, 500];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = grid.totalRows;
    final pages = grid.pageCount ?? 1;
    final first = total == 0 ? 0 : grid.query.offset + 1;
    final last = grid.query.offset + grid.result.rows.length;
    final label = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              total == null
                  ? 'Counting…'
                  : '$first–$last of $total rows · ${grid.result.elapsed.inMilliseconds} ms',
              style: label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!narrow) ...[
            Text('Rows per page', style: label),
            const SizedBox(width: 6),
            DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value:
                    _sizes.contains(grid.query.limit) ? grid.query.limit : null,
                hint: Text('${grid.query.limit}'),
                isDense: true,
                style: theme.textTheme.bodySmall,
                items: [
                  for (final s in _sizes)
                    DropdownMenuItem(value: s, child: Text('$s')),
                ],
                onChanged: (v) => v == null ? null : grid.setPageSize(v),
              ),
            ),
            const SizedBox(width: 12),
          ],
          IconButton(
            tooltip: 'First page',
            icon: const Icon(Icons.first_page_rounded),
            onPressed: grid.page > 0 ? () => grid.goToPage(0) : null,
          ),
          IconButton(
            tooltip: 'Previous page',
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed:
                grid.page > 0 ? () => grid.goToPage(grid.page - 1) : null,
          ),
          Text('${grid.page + 1} / $pages', style: label),
          IconButton(
            tooltip: 'Next page',
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: grid.page + 1 < pages
                ? () => grid.goToPage(grid.page + 1)
                : null,
          ),
          IconButton(
            tooltip: 'Last page',
            icon: const Icon(Icons.last_page_rounded),
            onPressed:
                grid.page + 1 < pages ? () => grid.goToPage(pages - 1) : null,
          ),
        ],
      ),
    );
  }
}
