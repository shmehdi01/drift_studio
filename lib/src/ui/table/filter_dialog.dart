import 'package:flutter/material.dart';

import '../../core/schema.dart';
import '../../core/table_query.dart';

/// Shows the filter builder and returns the new filter, or `null` if
/// cancelled. Pass [initial] to edit an existing filter.
Future<ColumnFilter?> showFilterDialog(
  BuildContext context, {
  required List<ColumnInfo> columns,
  ColumnFilter? initial,
  String? initialColumn,
}) =>
    showDialog<ColumnFilter>(
      context: context,
      builder: (_) => _FilterDialog(
        columns: columns,
        initial: initial,
        initialColumn: initialColumn,
      ),
    );

class _FilterDialog extends StatefulWidget {
  const _FilterDialog({
    required this.columns,
    this.initial,
    this.initialColumn,
  });

  final List<ColumnInfo> columns;
  final ColumnFilter? initial;
  final String? initialColumn;

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  late String _column = widget.initial?.column ??
      widget.initialColumn ??
      widget.columns.first.name;
  late FilterOperator _operator =
      widget.initial?.operator ?? _defaultOperator(_column);
  late final _value = TextEditingController(text: widget.initial?.value ?? '');

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  /// Text columns default to "contains", which is what people usually mean
  /// when they start filtering; numbers default to equality.
  FilterOperator _defaultOperator(String column) {
    final info = widget.columns.where((c) => c.name == column).firstOrNull;
    return info != null && info.affinity == ColumnAffinity.text
        ? FilterOperator.contains
        : FilterOperator.equals;
  }

  void _submit() => Navigator.of(context).pop(
        ColumnFilter(column: _column, operator: _operator, value: _value.text),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add filter' : 'Edit filter'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LabeledDropdown<String>(
              label: 'Column',
              value: _column,
              items: [
                for (final c in widget.columns)
                  DropdownMenuItem(
                    value: c.name,
                    child: Text(
                      c.declaredType.isEmpty
                          ? c.name
                          : '${c.name}  ·  ${c.declaredType.toLowerCase()}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _column = v ?? _column),
            ),
            const SizedBox(height: 12),
            _LabeledDropdown<FilterOperator>(
              label: 'Condition',
              value: _operator,
              items: [
                for (final op in FilterOperator.values)
                  DropdownMenuItem(value: op, child: Text(op.label)),
              ],
              onChanged: (v) => setState(() => _operator = v ?? _operator),
            ),
            if (_operator.needsValue) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _value,
                autofocus: true,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Value',
                  helperText: _operator == FilterOperator.inList
                      ? 'Comma-separated values'
                      : null,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Apply')),
      ],
    );
  }
}

/// A dropdown with a floating label. Built from [DropdownButton] inside an
/// [InputDecorator] so it works across Flutter versions without the
/// `value`/`initialValue` deprecation churn of `DropdownButtonFormField`.
class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            isDense: true,
            items: items,
            onChanged: onChanged,
          ),
        ),
      );
}
