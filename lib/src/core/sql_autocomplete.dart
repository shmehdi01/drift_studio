/// What a completion inserts.
enum SuggestionKind {
  /// A table or view name.
  table,

  /// A column name.
  column,

  /// An SQL keyword.
  keyword,

  /// A built-in function.
  function,
}

/// A single completion candidate.
class SqlSuggestion {
  /// Creates a suggestion.
  const SqlSuggestion({
    required this.label,
    required this.insertText,
    required this.kind,
    this.detail,
  });

  /// Text shown in the list.
  final String label;

  /// Text that replaces the word under the cursor.
  final String insertText;

  /// Category, used for the icon and ranking.
  final SuggestionKind kind;

  /// Secondary text such as a column type or owning table.
  final String? detail;
}

/// The word being completed and where it sits in the editor text.
class CompletionContext {
  /// Creates a context.
  const CompletionContext({
    required this.prefix,
    required this.start,
    required this.end,
    this.qualifier,
  });

  /// Partial word typed so far (without any `alias.` qualifier).
  final String prefix;

  /// Offset where the replaced range starts.
  final int start;

  /// Offset where the replaced range ends (the cursor).
  final int end;

  /// The `alias` in `alias.col`, if the word is qualified.
  final String? qualifier;
}

/// Schema-aware SQL completion for SQLite.
///
/// Deliberately heuristic: it tokenises just enough to know which tables a
/// query mentions and whether the cursor expects a table or a column. That
/// keeps it fast on every keystroke without a full SQL parser.
class SqlAutocomplete {
  /// Creates a completer over `table → columns` (with declared types).
  SqlAutocomplete(this.schema);

  /// Table/view name → ordered list of (column, declaredType).
  final Map<String, List<(String, String)>> schema;

  /// SQLite keywords offered as completions.
  static const keywords = [
    'SELECT',
    'FROM',
    'WHERE',
    'AND',
    'OR',
    'NOT',
    'NULL',
    'IS',
    'IN',
    'LIKE',
    'GLOB',
    'BETWEEN',
    'ORDER BY',
    'GROUP BY',
    'HAVING',
    'LIMIT',
    'OFFSET',
    'ASC',
    'DESC',
    'DISTINCT',
    'AS',
    'JOIN',
    'LEFT JOIN',
    'INNER JOIN',
    'CROSS JOIN',
    'ON',
    'USING',
    'UNION',
    'UNION ALL',
    'EXCEPT',
    'INTERSECT',
    'CASE',
    'WHEN',
    'THEN',
    'ELSE',
    'END',
    'EXISTS',
    'WITH',
    'INSERT INTO',
    'VALUES',
    'UPDATE',
    'SET',
    'DELETE FROM',
    'RETURNING',
    'CREATE',
    'TABLE',
    'INDEX',
    'VIEW',
    'DROP',
    'ALTER',
    'PRAGMA',
    'EXPLAIN QUERY PLAN',
    'COLLATE NOCASE',
    'CAST',
    'ESCAPE',
  ];

  /// SQLite core and JSON functions offered as completions.
  static const functions = [
    'COUNT',
    'SUM',
    'AVG',
    'MIN',
    'MAX',
    'TOTAL',
    'GROUP_CONCAT',
    'COALESCE',
    'IFNULL',
    'NULLIF',
    'IIF',
    'LENGTH',
    'LOWER',
    'UPPER',
    'TRIM',
    'LTRIM',
    'RTRIM',
    'SUBSTR',
    'REPLACE',
    'INSTR',
    'ROUND',
    'ABS',
    'TYPEOF',
    'HEX',
    'QUOTE',
    'RANDOM',
    'PRINTF',
    'FORMAT',
    'DATE',
    'TIME',
    'DATETIME',
    'JULIANDAY',
    'STRFTIME',
    'UNIXEPOCH',
    'JSON',
    'JSON_EXTRACT',
    'JSON_ARRAY',
    'JSON_OBJECT',
    'JSON_EACH',
    'JSON_GROUP_ARRAY',
    'ROW_NUMBER',
    'RANK',
    'LAG',
    'LEAD',
  ];

  static final _wordChar = RegExp(r'[A-Za-z0-9_$]');
  static final _plainIdentifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
  static final _keywordSet = {
    for (final k in keywords) ...k.split(' '),
    'TABLE',
    'GROUP',
    'ORDER',
    'INDEX',
    'KEY',
    'DEFAULT',
    'CHECK',
  };

  /// Locates the word under [cursor].
  static CompletionContext contextAt(String text, int cursor) {
    final end = cursor.clamp(0, text.length);
    var start = end;
    while (start > 0 && _wordChar.hasMatch(text[start - 1])) {
      start--;
    }
    String? qualifier;
    if (start > 0 && text[start - 1] == '.') {
      var qs = start - 1;
      while (qs > 0 && _wordChar.hasMatch(text[qs - 1])) {
        qs--;
      }
      qualifier = text.substring(qs, start - 1);
      if (qualifier.isEmpty) qualifier = null;
    }
    return CompletionContext(
      prefix: text.substring(start, end),
      start: start,
      end: end,
      qualifier: qualifier,
    );
  }

  /// Returns ranked suggestions for the cursor position, at most [limit].
  ///
  /// An empty prefix only produces suggestions after `alias.`, right after a
  /// table-position keyword, or when [force]d (Ctrl+Space), so the list
  /// doesn't pop up on every space.
  List<SqlSuggestion> suggest(
    String text,
    int cursor, {
    int limit = 40,
    bool force = false,
  }) {
    final ctx = contextAt(text, cursor);
    final aliases = _aliases(text);
    final prefix = ctx.prefix.toLowerCase();

    if (ctx.qualifier != null) {
      final table =
          aliases[ctx.qualifier!.toLowerCase()] ?? _findTable(ctx.qualifier!);
      if (table == null) return const [];
      return _rank(_columnsOf(table), prefix, limit);
    }

    final expectsTable = _expectsTable(text.substring(0, ctx.start));
    if (prefix.isEmpty && !expectsTable && !force) return const [];

    final tables = [
      for (final t in schema.keys)
        SqlSuggestion(
          label: t,
          insertText: quoteIfNeeded(t),
          kind: SuggestionKind.table,
          detail: '${schema[t]!.length} columns',
        ),
    ];
    if (expectsTable) return _rank(tables, prefix, limit);

    // Columns of tables the query already mentions come first; if none are
    // mentioned yet, columns of every table are offered.
    final mentioned = aliases.values.toSet();
    final columnSources = mentioned.isEmpty ? schema.keys : mentioned;
    final columns = [for (final t in columnSources) ..._columnsOf(t)];

    return _rank([
      ...columns,
      for (final k in keywords)
        SqlSuggestion(label: k, insertText: k, kind: SuggestionKind.keyword),
      for (final f in functions)
        SqlSuggestion(
          label: '$f()',
          insertText: '$f(',
          kind: SuggestionKind.function,
        ),
      ...tables,
    ], prefix, limit);
  }

  /// Quotes [identifier] only when SQLite requires it.
  static String quoteIfNeeded(String identifier) {
    if (_plainIdentifier.hasMatch(identifier) &&
        !_keywordSet.contains(identifier.toUpperCase())) {
      return identifier;
    }
    return '"${identifier.replaceAll('"', '""')}"';
  }

  List<SqlSuggestion> _columnsOf(String table) => [
        for (final (name, type) in schema[table] ?? const <(String, String)>[])
          SqlSuggestion(
            label: name,
            insertText: quoteIfNeeded(name),
            kind: SuggestionKind.column,
            detail: type.isEmpty ? table : '$type · $table',
          ),
      ];

  /// Prefix matches rank above substring matches; within a tier the original
  /// order (columns, keywords, functions, tables) is preserved.
  List<SqlSuggestion> _rank(
    List<SqlSuggestion> all,
    String prefix,
    int limit,
  ) {
    if (prefix.isEmpty) return all.take(limit).toList();
    final starts = <SqlSuggestion>[];
    final contains = <SqlSuggestion>[];
    final seen = <String>{};
    for (final s in all) {
      final l = s.label.toLowerCase();
      if (l == prefix || !seen.add('${s.kind}:${s.label}')) continue;
      if (l.startsWith(prefix)) {
        starts.add(s);
      } else if (prefix.length > 1 && l.contains(prefix)) {
        contains.add(s);
      }
    }
    return [...starts, ...contains].take(limit).toList();
  }

  bool _expectsTable(String before) => RegExp(
        r'\b(FROM|JOIN|INTO|UPDATE|TABLE|table_info|index_list|foreign_key_list)\s*\(?\s*$',
        caseSensitive: false,
      ).hasMatch(before);

  String? _findTable(String name) {
    final lower = name.toLowerCase();
    for (final t in schema.keys) {
      if (t.toLowerCase() == lower) return t;
    }
    return null;
  }

  /// Maps lower-cased table names and aliases to the real table name, for
  /// every `FROM`/`JOIN`/`UPDATE`/`INTO` reference in [sql].
  Map<String, String> _aliases(String sql) {
    final out = <String, String>{};
    final ref = RegExp(
      r'\b(?:FROM|JOIN|UPDATE|INTO)\s+("([^"]+)"|[A-Za-z_][A-Za-z0-9_]*)'
      r'(?:\s+(?:AS\s+)?([A-Za-z_][A-Za-z0-9_]*))?',
      caseSensitive: false,
    );
    for (final m in ref.allMatches(sql)) {
      final raw = m.group(2) ?? m.group(1)!;
      final table = _findTable(raw);
      if (table == null) continue;
      out[table.toLowerCase()] = table;
      final alias = m.group(3);
      if (alias != null && !_keywordSet.contains(alias.toUpperCase())) {
        out[alias.toLowerCase()] = table;
      }
    }
    return out;
  }
}
