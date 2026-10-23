import 'dart:convert';
import 'dart:typed_data';

import 'query_result.dart';

/// Converts query results to portable text formats for copying/sharing.
abstract final class ResultExporter {
  /// RFC 4180 CSV with a header row.
  static String toCsv(QueryResult result) {
    String cell(Object? v) {
      final s = v == null ? '' : formatPlain(v);
      if (s.contains(RegExp(r'[",\n\r]'))) {
        return '"${s.replaceAll('"', '""')}"';
      }
      return s;
    }

    final b = StringBuffer()..writeln(result.columns.map(cell).join(','));
    for (final row in result.rows) {
      b.writeln(row.map(cell).join(','));
    }
    return b.toString();
  }

  /// Pretty-printed JSON array of row objects. Blobs become base64.
  static String toJson(QueryResult result) =>
      const JsonEncoder.withIndent('  ').convert([
        for (var i = 0; i < result.rows.length; i++)
          _jsonRow(result.rowAsMap(i))
      ]);

  /// A single row as pretty-printed JSON.
  static String rowToJson(Map<String, Object?> row) =>
      const JsonEncoder.withIndent('  ').convert(_jsonRow(row));

  /// Markdown table, handy for pasting into tickets and PRs.
  static String toMarkdown(QueryResult result) {
    String cell(Object? v) => (v == null ? 'NULL' : formatPlain(v))
        .replaceAll('|', r'\|')
        .replaceAll('\n', ' ');
    final b = StringBuffer()
      ..writeln('| ${result.columns.map(cell).join(' | ')} |')
      ..writeln('|${List.filled(result.columns.length, ' --- ').join('|')}|');
    for (final row in result.rows) {
      b.writeln('| ${row.map(cell).join(' | ')} |');
    }
    return b.toString();
  }

  /// SQL `INSERT` statements that recreate the rows in [table].
  static String toInserts(QueryResult result, String table) {
    String lit(Object? v) => switch (v) {
          null => 'NULL',
          final num n => '$n',
          final bool b => b ? '1' : '0',
          final Uint8List bytes =>
            "X'${bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join()}'",
          _ => "'${v.toString().replaceAll("'", "''")}'",
        };
    final cols =
        result.columns.map((c) => '"${c.replaceAll('"', '""')}"').join(', ');
    final t = '"${table.replaceAll('"', '""')}"';
    return [
      for (final row in result.rows)
        'INSERT INTO $t ($cols) VALUES (${row.map(lit).join(', ')});',
    ].join('\n');
  }

  /// Plain text for a value: blobs as hex preview, everything else `toString`.
  static String formatPlain(Object v) => switch (v) {
        final Uint8List b =>
          '0x${b.take(64).map((e) => e.toRadixString(16).padLeft(2, '0')).join()}'
              '${b.length > 64 ? '…' : ''}',
        _ => v.toString(),
      };

  static Map<String, Object?> _jsonRow(Map<String, Object?> row) => {
        for (final e in row.entries)
          e.key: switch (e.value) {
            final Uint8List b => base64Encode(b),
            final BigInt b => b.toString(),
            final v => v,
          },
      };
}
