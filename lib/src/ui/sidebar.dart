import 'package:flutter/material.dart';

import '../controllers/studio_controller.dart';
import '../core/schema.dart';
import 'studio_theme.dart';

/// The object explorer: fuzzy search plus grouped tables and views with
/// live row counts.
class StudioSidebar extends StatefulWidget {
  /// Creates the sidebar.
  const StudioSidebar({super.key, required this.controller, this.onSelected});

  /// Studio state.
  final StudioController controller;

  /// Called after an object is picked (closes the drawer on phones).
  final VoidCallback? onSelected;

  @override
  State<StudioSidebar> createState() => _StudioSidebarState();
}

class _StudioSidebarState extends State<StudioSidebar> {
  late final _search =
      TextEditingController(text: widget.controller.sidebarFilter);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final tables = c.visibleObjects(DbObjectType.table);
          final views = c.visibleObjects(DbObjectType.view);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: _SearchField(
                    controller: _search, onChanged: c.setSidebarFilter),
              ),
              Expanded(
                child: c.loading && c.objects.isEmpty
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : _ObjectList(
                        controller: c,
                        tables: tables,
                        views: views,
                        onSelected: widget.onSelected,
                      ),
              ),
              if (c.info != null) _DbFooter(info: c.info!),
            ],
          );
        },
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Search tables or columns',
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  tooltip: 'Clear',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

class _ObjectList extends StatelessWidget {
  const _ObjectList({
    required this.controller,
    required this.tables,
    required this.views,
    required this.onSelected,
  });

  final StudioController controller;
  final List<DbObject> tables;
  final List<DbObject> views;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    if (tables.isEmpty && views.isEmpty) {
      return Center(
        child: Text(
          controller.sidebarFilter.isEmpty ? 'No tables' : 'No matches',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 12),
      children: [
        if (tables.isNotEmpty)
          _SectionHeader(label: 'Tables', count: tables.length),
        for (final t in tables)
          _ObjectTile(
              object: t, controller: controller, onSelected: onSelected),
        if (views.isNotEmpty)
          _SectionHeader(label: 'Views', count: views.length),
        for (final v in views)
          _ObjectTile(
              object: v, controller: controller, onSelected: onSelected),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Text(
        '${label.toUpperCase()}  ·  $count',
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ObjectTile extends StatelessWidget {
  const _ObjectTile({
    required this.object,
    required this.controller,
    required this.onSelected,
  });

  final DbObject object;
  final StudioController controller;
  final VoidCallback? onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = controller.selected?.name == object.name &&
        controller.pane != StudioPane.console;
    final count = controller.rowCount(object.name);
    final columns = controller.matchingColumns(object.name);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? scheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            controller.select(object);
            onSelected?.call();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Icon(
                  object.type == DbObjectType.view
                      ? Icons.visibility_outlined
                      : Icons.table_chart_outlined,
                  size: 16,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        object.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? scheme.onPrimaryContainer : null,
                        ),
                      ),
                      if (columns.isNotEmpty)
                        Text(
                          columns.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: monoStyle(context,
                              size: 10.5, color: scheme.primary),
                        ),
                    ],
                  ),
                ),
                if (count != null)
                  _CountBadge(count: count, selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      formatCount(count),
      style: monoStyle(
        context,
        size: 11,
        color: (selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant)
            .withValues(alpha: 0.75),
      ),
    );
  }
}

class _DbFooter extends StatelessWidget {
  const _DbFooter({required this.info});

  final DatabaseInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            Text('SQLite ${info.sqliteVersion}', style: style),
            Text('schema v${info.userVersion}', style: style),
            Text(formatBytes(info.sizeInBytes), style: style),
            Text(info.journalMode.toUpperCase(), style: style),
          ],
        ),
      ),
    );
  }
}

/// Compact row-count formatting: 1234 → 1.2K.
String formatCount(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(n < 10000 ? 1 : 0)}K';
  return '${(n / 1000000).toStringAsFixed(1)}M';
}

/// Human-readable byte size.
String formatBytes(int n) {
  if (n < 1024) return '$n B';
  if (n < 1048576) return '${(n / 1024).toStringAsFixed(0)} KB';
  if (n < 1073741824) return '${(n / 1048576).toStringAsFixed(1)} MB';
  return '${(n / 1073741824).toStringAsFixed(2)} GB';
}
