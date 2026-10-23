/// A professional, in-app database studio for Drift (SQLite) databases.
///
/// Open it with [DriftStudio.open] or push a [DriftStudio] widget. For
/// non-Drift databases implement [StudioDataSource] and use
/// [DriftStudio.withSource].
library;

import 'src/core/studio_data_source.dart';
import 'src/ui/drift_studio_page.dart';

export 'src/core/drift_data_source.dart' show DriftStudioDataSource;
export 'src/core/export.dart' show ResultExporter;
export 'src/core/query_result.dart' show QueryResult;
export 'src/core/saved_query.dart'
    show BuiltInQueries, InMemoryQueryStore, QueryStore, SavedQuery;
export 'src/core/schema.dart';
export 'src/core/schema_inspector.dart' show SchemaInspector;
export 'src/core/sql_autocomplete.dart';
export 'src/core/sql_utils.dart' show SqlUtils;
export 'src/core/studio_data_source.dart' show StudioDataSource;
export 'src/core/table_query.dart';
export 'src/drift_studio_config.dart' show DriftStudioConfig;
export 'src/ui/drift_studio_page.dart' show DriftStudio;
