/// Small, dependency-free helpers for working with SQLite SQL text.
abstract final class SqlUtils {
  /// Quotes an identifier so table/column names with spaces, keywords or
  /// quotes are always safe to interpolate.
  static String quote(String identifier) =>
      '"${identifier.replaceAll('"', '""')}"';

  /// Removes `-- line` and `/* block */` comments while leaving string
  /// literals and quoted identifiers intact.
  static String stripComments(String sql) {
    final out = StringBuffer();
    var i = 0;
    while (i < sql.length) {
      final c = sql[i];
      if (c == "'" || c == '"' || c == '`' || c == '[') {
        final close = c == '[' ? ']' : c;
        final end = _skipQuoted(sql, i, close);
        out.write(sql.substring(i, end));
        i = end;
      } else if (sql.startsWith('--', i)) {
        final nl = sql.indexOf('\n', i);
        i = nl == -1 ? sql.length : nl;
      } else if (sql.startsWith('/*', i)) {
        final end = sql.indexOf('*/', i + 2);
        i = end == -1 ? sql.length : end + 2;
        out.write(' ');
      } else {
        out.write(c);
        i++;
      }
    }
    return out.toString();
  }

  /// Splits a script into individual statements on top-level semicolons.
  ///
  /// Semicolons inside strings, quoted identifiers and comments are ignored.
  /// `CREATE TRIGGER ... BEGIN ...; END` bodies are kept together.
  static List<String> splitStatements(String sql) {
    final cleaned = stripComments(sql);
    final statements = <String>[];
    var start = 0;
    var i = 0;
    var blockDepth = 0;
    while (i < cleaned.length) {
      final c = cleaned[i];
      if (c == "'" || c == '"' || c == '`' || c == '[') {
        i = _skipQuoted(cleaned, i, c == '[' ? ']' : c);
        continue;
      }
      if (_isWordAt(cleaned, i, 'BEGIN') &&
          _isTriggerSoFar(cleaned, start, i)) {
        blockDepth++;
      } else if (blockDepth > 0 && _isWordAt(cleaned, i, 'CASE')) {
        // CASE ... END inside a trigger body must not close the body early.
        blockDepth++;
      } else if (_isWordAt(cleaned, i, 'END') && blockDepth > 0) {
        blockDepth--;
      } else if (c == ';' && blockDepth == 0) {
        final s = cleaned.substring(start, i).trim();
        if (s.isNotEmpty) statements.add(s);
        start = i + 1;
      }
      i++;
    }
    final tail = cleaned.substring(start).trim();
    if (tail.isNotEmpty) statements.add(tail);
    return statements;
  }

  /// Whether [statement] only reads data.
  ///
  /// This is a conservative keyword check used to enforce read-only mode: a
  /// statement is only treated as a read when it starts with a read keyword
  /// and contains no data-modifying keyword at the top level of a CTE.
  static bool isReadOnly(String statement) {
    final s = stripComments(statement).trim().toUpperCase();
    if (s.isEmpty) return true;
    final first = s.split(RegExp(r'[\s(]+')).first;
    switch (first) {
      case 'SELECT':
      case 'VALUES':
      case 'EXPLAIN':
        return true;
      case 'PRAGMA':
        // `PRAGMA x = y` and `PRAGMA x(y)` mutate settings; bare reads don't,
        // except for the table-valued pragmas that take a table name.
        if (s.contains('=')) return false;
        return !RegExp(r'^PRAGMA\s+\w+\s*\(').hasMatch(s) ||
            _readPragmaWithArg.hasMatch(s);
      case 'WITH':
        return !RegExp(r'\b(INSERT|UPDATE|DELETE|REPLACE)\b')
            .hasMatch(_withoutLiterals(s));
      default:
        return false;
    }
  }

  /// Whether [statement] produces a result set (reads, or `RETURNING`).
  static bool returnsRows(String statement) {
    final s = stripComments(statement).trim().toUpperCase();
    return isReadOnly(statement) ||
        RegExp(r'\bRETURNING\b').hasMatch(_withoutLiterals(s));
  }

  /// Escapes `%`, `_` and the escape character for a `LIKE ... ESCAPE '\'`.
  static String escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  static final _readPragmaWithArg = RegExp(
    r'^PRAGMA\s+(TABLE_INFO|TABLE_XINFO|INDEX_LIST|INDEX_INFO|INDEX_XINFO|'
    r'FOREIGN_KEY_LIST|FOREIGN_KEY_CHECK|INTEGRITY_CHECK|QUICK_CHECK)\s*\(',
  );

  static String _withoutLiterals(String s) =>
      s.replaceAll(RegExp(r"'(?:[^']|'')*'"), "''");

  static int _skipQuoted(String sql, int start, String close) {
    var i = start + 1;
    while (i < sql.length) {
      if (sql[i] == close) {
        // A doubled quote is an escaped quote, not the end of the literal.
        if (close != ']' && i + 1 < sql.length && sql[i + 1] == close) {
          i += 2;
          continue;
        }
        return i + 1;
      }
      i++;
    }
    return sql.length;
  }

  static bool _isWordAt(String s, int i, String word) {
    if (i + word.length > s.length) return false;
    if (s.substring(i, i + word.length).toUpperCase() != word) return false;
    final before = i == 0 ? ' ' : s[i - 1];
    final after = i + word.length >= s.length ? ' ' : s[i + word.length];
    return !_isWordChar(before) && !_isWordChar(after);
  }

  static bool _isTriggerSoFar(String s, int start, int i) =>
      RegExp(r'\bCREATE\s+(TEMP\w*\s+)?TRIGGER\b', caseSensitive: false)
          .hasMatch(s.substring(start, i));

  static bool _isWordChar(String c) => RegExp(r'[A-Za-z0-9_$]').hasMatch(c);
}
