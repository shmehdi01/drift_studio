import 'package:flutter/material.dart';

import '../controllers/studio_controller.dart';
import '../core/schema.dart';
import 'studio_theme.dart';
import 'widgets/feedback.dart';

/// Shows a table's columns, indexes, foreign keys, triggers and DDL.
class StructurePane extends StatelessWidget {
  /// Creates the pane.
  const StructurePane({super.key, required this.studio, required this.details});

  /// Root controller, for following foreign keys.
  final StudioController studio;

  /// The table to describe.
  final TableDetails details;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _Section(
          title: 'Columns',
          count: details.columns.length,
          child: _ColumnsTable(details: details),
        ),
        if (details.indexes.isNotEmpty)
          _Section(
            title: 'Indexes',
            count: details.indexes.length,
            child: Column(
              children: [
                for (final i in details.indexes)
                  _Line(
                    leading: i.unique ? 'UNIQUE' : 'INDEX',
                    title: i.name,
                    detail:
                        '(${i.columns.join(', ')})  ·  ${_origin(i.origin)}',
                  ),
              ],
            ),
          ),
        if (details.foreignKeys.isNotEmpty)
          _Section(
            title: 'Foreign keys',
            count: details.foreignKeys.length,
            child: Column(
              children: [
                for (final f in details.foreignKeys)
                  _Line(
                    leading: 'FK',
                    title:
                        '${f.fromColumn} → ${f.table}.${f.toColumn ?? 'rowid'}',
                    detail:
                        'on update ${f.onUpdate.toLowerCase()} · on delete ${f.onDelete.toLowerCase()}',
                    onTap: () => studio.select(
                      studio.objects.firstWhere((o) => o.name == f.table,
                          orElse: () => details.object),
                      pane: StudioPane.structure,
                    ),
                  ),
              ],
            ),
          ),
        if (details.triggers.isNotEmpty)
          _Section(
            title: 'Triggers',
            count: details.triggers.length,
            child: Column(
              children: [
                for (final t in details.triggers)
                  _SqlBlock(title: t.name, sql: t.sql ?? ''),
              ],
            ),
          ),
        if (details.object.sql != null)
          _Section(
            title: 'Definition',
            child: _SqlBlock(sql: details.object.sql!),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.travel_explore_rounded, size: 18),
            label: const Text('Find NULLs in every column'),
            onPressed: () => studio.openInConsole(_nullReport()),
          ),
        ),
      ],
    );
  }

  /// A one-shot data-quality query: how many NULLs each column holds.
  String _nullReport() {
    final t = '"${details.object.name.replaceAll('"', '""')}"';
    final parts = [
      for (final c in details.columns)
        "SELECT '${c.name.replaceAll("'", "''")}' AS column_name, "
            'COUNT(*) - COUNT("${c.name.replaceAll('"', '""')}") AS null_count FROM $t',
    ];
    return '${parts.join('\nUNION ALL\n')}\nORDER BY null_count DESC;';
  }

  static String _origin(String o) => switch (o) {
        'pk' => 'primary key',
        'u' => 'unique constraint',
        _ => 'created',
      };
}

class _ColumnsTable extends StatelessWidget {
  const _ColumnsTable({required this.details});

  final TableDetails details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fkColumns = {for (final f in details.foreignKeys) f.fromColumn: f};
    final head = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: scheme.onSurfaceVariant,
      letterSpacing: 0.4,
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 36,
        dataRowMaxHeight: 44,
        horizontalMargin: 12,
        columnSpacing: 28,
        headingTextStyle: head,
        columns: const [
          DataColumn(label: Text('#'), numeric: true),
          DataColumn(label: Text('NAME')),
          DataColumn(label: Text('TYPE')),
          DataColumn(label: Text('CONSTRAINTS')),
          DataColumn(label: Text('DEFAULT')),
        ],
        rows: [
          for (final c in details.columns)
            DataRow(cells: [
              DataCell(Text('${c.position + 1}',
                  style: monoStyle(context,
                      size: 11, color: scheme.onSurfaceVariant))),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (c.isPrimaryKey)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(Icons.key_rounded,
                          size: 14, color: scheme.primary),
                    ),
                  Text(c.name,
                      style: monoStyle(context)
                          .copyWith(fontWeight: FontWeight.w600)),
                ],
              )),
              DataCell(Text(
                c.declaredType.isEmpty ? '—' : c.declaredType,
                style: monoStyle(context, color: scheme.tertiary),
              )),
              DataCell(Wrap(
                spacing: 4,
                children: [
                  if (c.isPrimaryKey) _Badge('PK', scheme.primary),
                  if (c.notNull) _Badge('NOT NULL', scheme.secondary),
                  if (fkColumns[c.name] != null)
                    _Badge('FK → ${fkColumns[c.name]!.table}', scheme.tertiary),
                ],
              )),
              DataCell(Text(
                c.defaultValue ?? '',
                style: monoStyle(context, color: scheme.onSurfaceVariant),
              )),
            ]),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700, color: color),
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.count});

  final String title;
  final int? count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              count == null ? title : '$title  ·  $count',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
                borderRadius: BorderRadius.circular(10), child: child),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(
      {required this.leading,
      required this.title,
      required this.detail,
      this.onTap});

  final String leading;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: _Badge(leading, scheme.primary),
      title: Text(title,
          style: monoStyle(context).copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(detail,
          style: monoStyle(context, size: 11, color: scheme.onSurfaceVariant)),
      trailing: onTap == null
          ? null
          : const Icon(Icons.chevron_right_rounded, size: 18),
    );
  }
}

class _SqlBlock extends StatelessWidget {
  const _SqlBlock({required this.sql, this.title});

  final String sql;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(title!,
                        style: Theme.of(context).textTheme.labelLarge),
                  ),
                SelectableText(sql, style: monoStyle(context)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy SQL',
            icon: const Icon(Icons.copy_rounded, size: 16),
            onPressed: () => copyToClipboard(context, sql, label: 'SQL copied'),
          ),
        ],
      ),
    );
  }
}
