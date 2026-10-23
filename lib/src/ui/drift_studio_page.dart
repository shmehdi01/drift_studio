import 'package:drift/drift.dart' show GeneratedDatabase;
import 'package:flutter/material.dart';

import '../controllers/studio_controller.dart';
import '../core/drift_data_source.dart';
import '../core/schema.dart';
import '../core/studio_data_source.dart';
import '../drift_studio_config.dart';
import 'console/console_pane.dart';
import 'sidebar.dart';
import 'structure_pane.dart';
import 'studio_theme.dart';
import 'table/data_pane.dart';
import 'widgets/feedback.dart';

/// A full-screen database studio.
///
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => DriftStudio(database: myDatabase),
/// ));
/// ```
class DriftStudio extends StatefulWidget {
  /// Opens the studio on a Drift database.
  DriftStudio({
    super.key,
    required GeneratedDatabase database,
    this.config = const DriftStudioConfig(),
  }) : source = DriftStudioDataSource(database);

  /// Opens the studio on any [StudioDataSource] (sqflite, sqlite3, …).
  const DriftStudio.withSource({
    super.key,
    required this.source,
    this.config = const DriftStudioConfig(),
  });

  /// The database being inspected.
  final StudioDataSource source;

  /// Behaviour and content options.
  final DriftStudioConfig config;

  /// Pushes the studio as a new route.
  static Future<void> open(
    BuildContext context,
    GeneratedDatabase database, {
    DriftStudioConfig config = const DriftStudioConfig(),
  }) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DriftStudio(database: database, config: config),
      ));

  @override
  State<DriftStudio> createState() => _DriftStudioState();
}

class _DriftStudioState extends State<DriftStudio> {
  late final StudioController _controller = StudioController(
    source: widget.source,
    config: widget.config,
  );
  final _scaffold = GlobalKey<ScaffoldState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.config.theme ?? buildStudioTheme(Theme.of(context));
    return Theme(
      data: theme,
      child: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 840;
        final sidebar = StudioSidebar(
          controller: _controller,
          onSelected: wide ? null : () => _scaffold.currentState?.closeDrawer(),
        );
        return Scaffold(
          key: _scaffold,
          drawer:
              wide ? null : Drawer(width: 300, child: SafeArea(child: sidebar)),
          appBar: _appBar(context, wide),
          body: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) =>
                _controller.error != null && _controller.objects.isEmpty
                    ? StudioMessage(
                        icon: Icons.error_outline_rounded,
                        title: 'Could not read the database',
                        detail: '${_controller.error}',
                        isError: true,
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (wide) SizedBox(width: 280, child: sidebar),
                          if (wide) const VerticalDivider(width: 1),
                          Expanded(child: _MainArea(controller: _controller)),
                        ],
                      ),
          ),
        );
      }),
    );
  }

  PreferredSizeWidget _appBar(BuildContext context, bool wide) {
    final theme = Theme.of(context);
    return AppBar(
      automaticallyImplyLeading: true,
      leading: wide
          ? null
          : IconButton(
              tooltip: 'Tables',
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => _scaffold.currentState?.openDrawer(),
            ),
      title: Row(
        children: [
          Icon(Icons.storage_rounded,
              size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              widget.config.title ?? widget.source.name,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Reload schema',
          icon: const Icon(Icons.sync_rounded),
          onPressed: _controller.load,
        ),
        if (Navigator.of(context).canPop())
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        const SizedBox(width: 4),
      ],
      bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1), child: Divider()),
    );
  }
}

class _MainArea extends StatelessWidget {
  const _MainArea({required this.controller});

  final StudioController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selected = controller.selected;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PaneHeader(controller: controller),
            const Divider(),
            Expanded(
              child: switch (controller.pane) {
                StudioPane.console => ConsolePane(studio: controller),
                _ when controller.loading && controller.objects.isEmpty =>
                  const Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                _ when selected == null => const StudioMessage(
                    icon: Icons.table_chart_outlined,
                    title: 'Select a table',
                  ),
                _ => _TablePane(
                    key: ValueKey('${selected.name}/${controller.pane}'),
                    controller: controller,
                    object: selected,
                  ),
              },
            ),
          ],
        );
      },
    );
  }
}

class _PaneHeader extends StatelessWidget {
  const _PaneHeader({required this.controller});

  final StudioController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = controller.selected;
    final count = selected == null ? null : controller.rowCount(selected.name);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          if (selected != null && controller.pane != StudioPane.console) ...[
            Flexible(
              child: Text(
                selected.name,
                overflow: TextOverflow.ellipsis,
                style: monoStyle(context, size: 15)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            if (selected.type == DbObjectType.view)
              const Chip(label: Text('view')),
            if (count != null && !narrow)
              Text(
                '${formatCount(count)} rows',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
          ] else
            Text('SQL console',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          SegmentedButton<StudioPane>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              ButtonSegment(
                value: StudioPane.data,
                icon: const Icon(Icons.grid_on_rounded, size: 16),
                label: narrow ? null : const Text('Data'),
                tooltip: 'Data',
              ),
              ButtonSegment(
                value: StudioPane.structure,
                icon: const Icon(Icons.account_tree_outlined, size: 16),
                label: narrow ? null : const Text('Structure'),
                tooltip: 'Structure',
              ),
              ButtonSegment(
                value: StudioPane.console,
                icon: const Icon(Icons.terminal_rounded, size: 16),
                label: narrow ? null : const Text('SQL'),
                tooltip: 'SQL console',
              ),
            ],
            selected: {controller.pane},
            onSelectionChanged: (s) => controller.showPane(s.first),
          ),
        ],
      ),
    );
  }
}

class _TablePane extends StatelessWidget {
  const _TablePane({super.key, required this.controller, required this.object});

  final StudioController controller;
  final DbObject object;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<TableDetails>(
      future: controller.details(object),
      builder: (context, snap) {
        if (snap.hasError) {
          return StudioMessage(
            icon: Icons.error_outline_rounded,
            title: 'Could not describe ${object.name}',
            detail: '${snap.error}',
            isError: true,
          );
        }
        final details = snap.data;
        if (details == null) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        return controller.pane == StudioPane.structure
            ? StructurePane(studio: controller, details: details)
            : DataPane(studio: controller, details: details);
      },
    );
  }
}
