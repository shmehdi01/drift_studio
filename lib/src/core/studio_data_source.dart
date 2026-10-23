import 'query_result.dart';

/// The only bridge between Drift Studio and a database.
///
/// Every screen talks to the database through this interface, so the studio
/// can sit on top of Drift, sqflite or any other SQLite binding by
/// implementing three methods.
abstract class StudioDataSource {
  /// A human-friendly label for the database, shown in the sidebar header.
  String get name;

  /// Runs a read statement and returns its rows.
  Future<QueryResult> select(String sql, [List<Object?> args = const []]);

  /// Runs a write or DDL statement and returns the number of changed rows.
  Future<int> execute(String sql, [List<Object?> args = const []]);

  /// Called after a successful write so the host app can refresh any live
  /// queries (for example Drift streams). The default does nothing.
  Future<void> onDataChanged() async {}
}
