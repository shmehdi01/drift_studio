import 'package:flutter/material.dart';

import 'core/saved_query.dart';

/// Behaviour and content options for the studio.
class DriftStudioConfig {
  /// Creates a configuration. The defaults are safe for production builds:
  /// writes are blocked and nothing is persisted.
  const DriftStudioConfig({
    this.title,
    this.allowWrites = false,
    this.confirmWrites = true,
    this.pageSize = 50,
    this.presetQueries = const [],
    this.queryStore,
    this.showInternalTables = false,
    this.theme,
    this.historyLimit = 50,
  });

  /// Title for the app bar; defaults to the data source name.
  final String? title;

  /// Allows `INSERT`/`UPDATE`/`DELETE`/DDL from the console and in-grid
  /// editing. When `false`, only read statements run.
  final bool allowWrites;

  /// Asks for confirmation before every write when [allowWrites] is on.
  final bool confirmWrites;

  /// Rows per page in the data grid.
  final int pageSize;

  /// App-specific queries listed in the console's snippet panel, for example
  /// "Unsynced orders" or "Today's invoices". Placeholders `{{table}}` and
  /// `{{column}}` are supported.
  final List<SavedQuery> presetQueries;

  /// Where user-saved queries and history live. Defaults to in-memory.
  final QueryStore? queryStore;

  /// Lists `sqlite_*` internal tables in the sidebar.
  final bool showInternalTables;

  /// Overrides the studio theme. By default the studio derives a compact,
  /// data-dense theme from the surrounding app theme.
  final ThemeData? theme;

  /// Maximum number of history entries kept.
  final int historyLimit;
}
