import 'package:flutter/material.dart';

import '../../controllers/sql_console_controller.dart';
import '../../controllers/studio_controller.dart';
import '../../core/saved_query.dart';
import '../studio_theme.dart';
import '../table/row_inspector.dart';
import '../widgets/data_grid.dart';
import '../widgets/export_menu.dart';
import '../widgets/feedback.dart';
import 'sql_editor.dart';

/// The SQL console: editor, snippet library, history and results.
class ConsolePane extends StatelessWidget {
  /// Creates the console.
  const ConsolePane({super.key, required this.studio});

  /// Root controller.
  final StudioController studio;

  SqlConsoleController get _console => studio.console;

  Future<void> _run(BuildContext context) => _console.run(
        confirm: (writes) => confirmAction(
          context,
          title: writes.length == 1
              ? 'Run write statement?'
              : 'Run ${writes.length} write statements?',
          message: 'These statements modify the database used by the app.',
          code: writes.join(';\n\n'),
        ),
      );

  /// Loads [q] into the editor, filling placeholders from the selected table.
  void _useSnippet(SavedQuery q, {bool run = false, BuildContext? context}) {
    final table = studio.selected?.name;
    final sql = q.resolve(
      table: table,
      column: table == null ? null : studio.templateColumnOf(table),
    );
    _console.load(sql);
    if (run && context != null) _run(context);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      final main = _EditorAndResults(
        studio: studio,
        onRun: () => _run(context),
        onShowLibrary: wide
            ? null
            : () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (sheet) => SizedBox(
                    height: MediaQuery.sizeOf(sheet).height * 0.7,
                    child: _Library(
                      console: _console,
                      onUse: (q, run) {
                        Navigator.of(sheet).pop();
                        _useSnippet(q, run: run, context: context);
                      },
                      onUseHistory: (sql) {
                        Navigator.of(sheet).pop();
                        _console.load(sql);
                      },
                    ),
                  ),
                ),
      );
      if (!wide) return main;
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 270,
            child: _Library(
              console: _console,
              onUse: (q, run) => _useSnippet(q, run: run, context: context),
              onUseHistory: _console.load,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: main),
        ],
      );
    });
  }
}

class _EditorAndResults extends StatefulWidget {
  const _EditorAndResults({
    required this.studio,
    required this.onRun,
    required this.onShowLibrary,
  });

  final StudioController studio;
  final VoidCallback onRun;
  final VoidCallback? onShowLibrary;

  @override
  State<_EditorAndResults> createState() => _EditorAndResultsState();
}

class _EditorAndResultsState extends State<_EditorAndResults> {
  // Editor/results split; view-only state, like a desktop splitter.
  double _split = 0.38;

  @override
  Widget build(BuildContext context) {
    final console = widget.studio.console;
    return LayoutBuilder(builder: (context, box) {
      final editorHeight =
          (box.maxHeight * _split).clamp(96.0, box.maxHeight - 140);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ConsoleToolbar(
            studio: widget.studio,
            onRun: widget.onRun,
            onShowLibrary: widget.onShowLibrary,
          ),
          const Divider(),
          SizedBox(
            height: editorHeight,
            child: SqlEditor(
              controller: console.editor,
              autocomplete: () => widget.studio.autocomplete,
              onRun: widget.onRun,
            ),
          ),
          _SplitHandle(
            onDrag: (dy) => setState(() {
              _split = ((editorHeight + dy) / box.maxHeight).clamp(0.15, 0.8);
            }),
          ),
          Expanded(child: _Results(console: console)),
        ],
      );
    });
  }
}

class _ConsoleToolbar extends StatelessWidget {
  const _ConsoleToolbar({
    required this.studio,
    required this.onRun,
    required this.onShowLibrary,
  });

  final StudioController studio;
  final VoidCallback onRun;
  final VoidCallback? onShowLibrary;

  @override
  Widget build(BuildContext context) {
    final console = studio.console;
    final scheme = Theme.of(context).colorScheme;
    final writes = studio.config.allowWrites;
    return ListenableBuilder(
      listenable: console,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            FilledButton.icon(
              onPressed: console.running ? null : onRun,
              icon: console.running
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Run'),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Ctrl/⌘ + Enter runs the selection, or everything.\n'
                  'Ctrl + Space shows suggestions.',
              child: Icon(Icons.keyboard_outlined,
                  size: 18, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: writes
                  ? 'Writes are enabled for this studio'
                  : 'Only SELECT, PRAGMA reads and EXPLAIN can run',
              child: Chip(
                avatar: Icon(
                  writes ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                  size: 14,
                  color: writes ? scheme.error : scheme.primary,
                ),
                label: Text(writes ? 'Writes on' : 'Read-only'),
              ),
            ),
            const Spacer(),
            if (onShowLibrary != null)
              IconButton(
                tooltip: 'Snippets & history',
                icon: const Icon(Icons.library_books_outlined, size: 20),
                onPressed: onShowLibrary,
              ),
            IconButton(
              tooltip: 'Save query',
              icon: const Icon(Icons.bookmark_add_outlined, size: 20),
              onPressed: () => _save(context),
            ),
            IconButton(
              tooltip: 'Clear editor',
              icon: const Icon(Icons.clear_all_rounded, size: 20),
              onPressed: () => console.load(''),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final console = studio.console;
    if (console.editor.text.trim().isEmpty) return;
    final name = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save query'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Name'),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(name.text),
              child: const Text('Save')),
        ],
      ),
    );
    name.dispose();
    if (title == null || title.trim().isEmpty) return;
    await console.saveCurrent(title.trim());
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
            content: Text('Saved "$title"'),
            behavior: SnackBarBehavior.floating,
            width: 280),
      );
    }
  }
}

class _SplitHandle extends StatelessWidget {
  const _SplitHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
        child: Container(
          height: 10,
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            border: Border.symmetric(
                horizontal: BorderSide(color: scheme.outlineVariant)),
          ),
          alignment: Alignment.center,
          child: Container(
            width: 36,
            height: 3,
            decoration: BoxDecoration(
              color: scheme.outline.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.console});

  final SqlConsoleController console;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: console,
      builder: (context, _) {
        final error = console.error;
        final result = console.result;
        if (console.running && result == null) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (error != null) {
          return StudioMessage(
            icon: error is WritesDisabledException
                ? Icons.lock_outline_rounded
                : Icons.error_outline_rounded,
            title: error is WritesDisabledException
                ? 'Blocked in read-only mode'
                : 'Query failed',
            detail: '$error',
            isError: true,
          );
        }
        if (result == null) {
          return const StudioMessage(
            icon: Icons.terminal_rounded,
            title: 'Run a query to see results',
            detail: 'Pick a snippet, or type and press Ctrl/⌘ + Enter',
          );
        }
        final theme = Theme.of(context);
        final status = [
          if (result.columns.isNotEmpty) '${result.rows.length} rows',
          if (result.affectedRows != null)
            '${result.affectedRows} rows affected',
          if (console.statementCount > 1)
            '${console.statementCount} statements',
          '${result.elapsed.inMilliseconds} ms',
        ].join(' · ');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: result.columns.isEmpty
                  ? StudioMessage(
                      icon: Icons.check_circle_outline_rounded,
                      title: result.isWrite
                          ? 'Statement executed'
                          : 'No rows returned',
                    )
                  : StudioDataGrid(
                      result: result,
                      onRowTap: (row) => showRowInspector(
                        context,
                        result: result,
                        index: row,
                        title: 'Result row ${row + 1}',
                      ),
                    ),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      status,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                  ExportMenu(result: result),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Library extends StatefulWidget {
  const _Library({
    required this.console,
    required this.onUse,
    required this.onUseHistory,
  });

  final SqlConsoleController console;
  final void Function(SavedQuery query, bool run) onUse;
  final ValueChanged<String> onUseHistory;

  @override
  State<_Library> createState() => _LibraryState();
}

class _LibraryState extends State<_Library> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        child: Column(
          children: [
            const TabBar(
              tabs: [Tab(text: 'Snippets'), Tab(text: 'History')],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: TextField(
                onChanged: (v) => setState(() => _filter = v.toLowerCase()),
                decoration: const InputDecoration(
                  hintText: 'Filter',
                  prefixIcon: Icon(Icons.search_rounded, size: 18),
                ),
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: widget.console,
                builder: (context, _) => TabBarView(
                  children: [_snippets(context), _history(context)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _snippets(BuildContext context) {
    final theme = Theme.of(context);
    final all = widget.console.snippets.where((q) =>
        _filter.isEmpty ||
        q.title.toLowerCase().contains(_filter) ||
        q.sql.toLowerCase().contains(_filter));
    final groups = <String, List<SavedQuery>>{};
    for (final q in all) {
      (groups[q.group] ??= []).add(q);
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Text(
              entry.key.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final q in entry.value)
            ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              title: Text(q.title),
              subtitle: q.description == null
                  ? null
                  : Text(q.description!,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => widget.onUse(q, false),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (q.group == 'Saved')
                    IconButton(
                      tooltip: 'Delete',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      onPressed: () => widget.console.deleteSaved(q.id),
                    ),
                  IconButton(
                    tooltip: 'Run',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    onPressed: () => widget.onUse(q, true),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _history(BuildContext context) {
    final items = widget.console.history
        .where((h) => _filter.isEmpty || h.toLowerCase().contains(_filter))
        .toList();
    if (items.isEmpty) {
      return const StudioMessage(
          icon: Icons.history_rounded, title: 'No history yet');
    }
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                const Divider(indent: 12, endIndent: 12),
            itemBuilder: (context, i) => InkWell(
              onTap: () => widget.onUseHistory(items[i]),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Text(
                  items[i],
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style:
                      monoStyle(context, size: 11.5, color: scheme.onSurface),
                ),
              ),
            ),
          ),
        ),
        TextButton.icon(
          onPressed: widget.console.clearHistory,
          icon: const Icon(Icons.delete_sweep_outlined, size: 18),
          label: const Text('Clear history'),
        ),
      ],
    );
  }
}
