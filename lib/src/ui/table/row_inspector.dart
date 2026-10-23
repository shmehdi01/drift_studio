import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/export.dart';
import '../../core/query_result.dart';
import '../../core/schema.dart';
import '../studio_theme.dart';
import '../widgets/cell_value.dart';
import '../widgets/feedback.dart';

/// Actions the inspector can trigger on its row.
class RowInspectorActions {
  /// Creates the action set; `null` callbacks hide their buttons.
  const RowInspectorActions({
    this.onEdit,
    this.onDelete,
    this.onFollowForeignKey,
  });

  /// Saves a new value for a column.
  final Future<void> Function(String column, Object? value)? onEdit;

  /// Deletes the row.
  final Future<void> Function()? onDelete;

  /// Opens the row referenced by a foreign key.
  final void Function(ForeignKeyInfo fk, Object? value)? onFollowForeignKey;
}

/// Slides in a side panel showing every field of row [index] in [result].
Future<void> showRowInspector(
  BuildContext context, {
  required QueryResult result,
  required int index,
  required String title,
  TableDetails? details,
  RowInspectorActions actions = const RowInspectorActions(),
}) {
  final theme = Theme.of(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close row inspector',
    barrierColor: Colors.black26,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => Theme(
      data: theme,
      child: Align(
        alignment: Alignment.centerRight,
        child: Material(
          elevation: 12,
          color: theme.colorScheme.surface,
          child: SizedBox(
            width: (MediaQuery.sizeOf(context).width * 0.92).clamp(0.0, 540.0),
            height: double.infinity,
            child: SafeArea(
              child: _RowInspector(
                row: result.rowAsMap(index),
                title: title,
                details: details,
                actions: actions,
              ),
            ),
          ),
        ),
      ),
    ),
    transitionBuilder: (context, anim, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class _RowInspector extends StatelessWidget {
  const _RowInspector({
    required this.row,
    required this.title,
    required this.details,
    required this.actions,
  });

  final Map<String, Object?> row;
  final String title;
  final TableDetails? details;
  final RowInspectorActions actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(title, style: theme.textTheme.titleMedium),
              ),
              _InspectorMenu(
                  row: row, table: details?.object.name, actions: actions),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: row.length,
            separatorBuilder: (_, __) =>
                const Divider(indent: 16, endIndent: 16),
            itemBuilder: (context, i) {
              final name = row.keys.elementAt(i);
              return _FieldTile(
                name: name,
                value: row[name],
                column: details?.column(name),
                foreignKey: details?.foreignKeys
                    .where((f) => f.fromColumn == name)
                    .firstOrNull,
                actions: actions,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _InspectorMenu extends StatelessWidget {
  const _InspectorMenu({
    required this.row,
    required this.table,
    required this.actions,
  });

  final Map<String, Object?> row;
  final String? table;
  final RowInspectorActions actions;

  @override
  Widget build(BuildContext context) {
    final asResult =
        QueryResult(columns: row.keys.toList(), rows: [row.values.toList()]);
    return PopupMenuButton<String>(
      tooltip: 'Row actions',
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (v) async {
        switch (v) {
          case 'json':
            await copyToClipboard(context, ResultExporter.rowToJson(row),
                label: 'Row copied as JSON');
          case 'insert':
            await copyToClipboard(
              context,
              ResultExporter.toInserts(asResult, table ?? 'table'),
              label: 'Row copied as INSERT',
            );
          case 'delete':
            final ok = await confirmAction(
              context,
              title: 'Delete row?',
              message: 'This permanently deletes the row from "$table".',
              confirmLabel: 'Delete',
            );
            if (!ok || !context.mounted) return;
            try {
              await actions.onDelete!();
              if (context.mounted) Navigator.of(context).pop();
            } catch (e) {
              if (context.mounted) showStudioError(context, e);
            }
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'json', child: Text('Copy as JSON')),
        if (table != null)
          const PopupMenuItem(value: 'insert', child: Text('Copy as INSERT')),
        if (actions.onDelete != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'delete', child: Text('Delete row')),
        ],
      ],
    );
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.name,
    required this.value,
    required this.column,
    required this.foreignKey,
    required this.actions,
  });

  final String name;
  final Object? value;
  final ColumnInfo? column;
  final ForeignKeyInfo? foreignKey;
  final RowInspectorActions actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final date = ValueFormat.asDateTime(value, columnName: name);
    final kind = ValueFormat.kindOf(value);
    final canEdit = actions.onEdit != null && value is! Uint8List;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (column?.isPrimaryKey ?? false)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child:
                      Icon(Icons.key_rounded, size: 13, color: scheme.primary),
                ),
              Text(name,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  {
                    if (column != null && column!.declaredType.isNotEmpty)
                      column!.declaredType.toLowerCase(),
                    // Only adds information when the stored value differs
                    // from the declared type (e.g. JSON in a TEXT column).
                    _kindLabel(kind),
                  }.join(' · '),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
              if (foreignKey != null &&
                  value != null &&
                  actions.onFollowForeignKey != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Open ${foreignKey!.table} row',
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  onPressed: () {
                    Navigator.of(context).pop();
                    actions.onFollowForeignKey!(foreignKey!, value);
                  },
                ),
              if (canEdit)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Edit value',
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  onPressed: () => _edit(context),
                ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Copy value',
                icon: const Icon(Icons.copy_rounded, size: 16),
                onPressed: () =>
                    copyToClipboard(context, ValueFormat.full(value)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SelectableText(
            ValueFormat.full(value),
            style: monoStyle(
              context,
              color: value == null
                  ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
                  : null,
            ),
          ),
          if (date != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '≈ $date',
                style:
                    theme.textTheme.labelSmall?.copyWith(color: scheme.primary),
              ),
            ),
        ],
      ),
    );
  }

  static String _kindLabel(ValueKind k) => switch (k) {
        ValueKind.nil => 'null',
        ValueKind.number => 'number',
        ValueKind.text => 'text',
        ValueKind.json => 'json',
        ValueKind.blob => 'blob',
      };

  Future<void> _edit(BuildContext context) async {
    final result = await showDialog<(bool, String)>(
      context: context,
      builder: (_) => _EditValueDialog(column: name, initial: value),
    );
    if (result == null || !context.mounted) return;
    final (isNull, text) = result;
    final Object? newValue = isNull
        ? null
        : (column?.affinity.isNumeric ?? value is num)
            ? (num.tryParse(text) ?? text)
            : text;
    try {
      await actions.onEdit!(name, newValue);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      if (context.mounted) showStudioError(context, e);
    }
  }
}

class _EditValueDialog extends StatefulWidget {
  const _EditValueDialog({required this.column, required this.initial});

  final String column;
  final Object? initial;

  @override
  State<_EditValueDialog> createState() => _EditValueDialogState();
}

class _EditValueDialogState extends State<_EditValueDialog> {
  late final _text = TextEditingController(
    // Raw text, not the pretty-printed form, so saving doesn't reformat JSON.
    text: switch (widget.initial) {
      null => '',
      final String s => s,
      final v => v.toString(),
    },
  );
  late bool _isNull = widget.initial == null;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.column}'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _text,
              enabled: !_isNull,
              autofocus: true,
              minLines: 1,
              maxLines: 8,
              style: monoStyle(context),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _isNull,
              title: const Text('Set to NULL'),
              onChanged: (v) => setState(() => _isNull = v ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((_isNull, _text.text)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
