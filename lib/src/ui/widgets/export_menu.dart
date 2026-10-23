import 'package:flutter/material.dart';

import '../../core/export.dart';
import '../../core/query_result.dart';
import 'feedback.dart';

/// Copies the visible rows to the clipboard in a choice of formats.
class ExportMenu extends StatelessWidget {
  /// Creates the menu for [result].
  const ExportMenu({super.key, required this.result, this.tableName});

  /// Rows to export.
  final QueryResult result;

  /// Target table for `INSERT` export; hides that option when `null`.
  final String? tableName;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Copy rows',
      enabled: result.rows.isNotEmpty,
      icon: const Icon(Icons.ios_share_rounded, size: 19),
      onSelected: (format) {
        final n = result.rows.length;
        final (text, label) = switch (format) {
          'csv' => (ResultExporter.toCsv(result), 'Copied $n rows as CSV'),
          'json' => (ResultExporter.toJson(result), 'Copied $n rows as JSON'),
          'md' => (
              ResultExporter.toMarkdown(result),
              'Copied $n rows as Markdown'
            ),
          _ => (
              ResultExporter.toInserts(result, tableName!),
              'Copied $n INSERT statements'
            ),
        };
        copyToClipboard(context, text, label: label);
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'csv', child: Text('Copy as CSV')),
        const PopupMenuItem(value: 'json', child: Text('Copy as JSON')),
        const PopupMenuItem(value: 'md', child: Text('Copy as Markdown table')),
        if (tableName != null)
          const PopupMenuItem(
              value: 'sql', child: Text('Copy as INSERT statements')),
      ],
    );
  }
}
