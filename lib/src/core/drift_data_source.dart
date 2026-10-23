import 'package:drift/drift.dart';

import 'query_result.dart';
import 'studio_data_source.dart';

/// A [StudioDataSource] backed by a Drift [GeneratedDatabase].
///
/// Statements run on the database's own executor, so the studio sees exactly
/// the data the app sees, through the same connection.
class DriftStudioDataSource extends StudioDataSource {
  /// Wraps [database]. [name] defaults to the database class name.
  DriftStudioDataSource(this.database, {String? name})
      : name = name ?? database.runtimeType.toString();

  /// The wrapped Drift database.
  final GeneratedDatabase database;

  @override
  final String name;

  @override
  Future<QueryResult> select(String sql,
      [List<Object?> args = const []]) async {
    final watch = Stopwatch()..start();
    final rows = await database.customSelect(
      sql,
      variables: [for (final a in args) Variable<Object>(a)],
    ).get();
    watch.stop();
    return QueryResult.fromMaps(
      [for (final r in rows) r.data],
      elapsed: watch.elapsed,
    );
  }

  @override
  Future<int> execute(String sql, [List<Object?> args = const []]) {
    return database.customUpdate(
      sql,
      variables: [for (final a in args) Variable<Object>(a)],
    );
  }

  @override
  Future<void> onDataChanged() async {
    // The studio cannot know which tables a free-form statement touched, so
    // every table is marked dirty to keep the app's streams honest.
    database.markTablesUpdated(database.allTables);
  }
}
