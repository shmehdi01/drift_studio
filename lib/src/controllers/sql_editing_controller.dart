import 'package:flutter/material.dart';

import '../core/sql_autocomplete.dart';

/// Colours used for SQL syntax highlighting.
class SqlHighlightColors {
  /// Creates a palette.
  const SqlHighlightColors({
    required this.keyword,
    required this.function,
    required this.string,
    required this.number,
    required this.comment,
    required this.identifier,
  });

  /// Derives a palette that reads well on [scheme]'s surface.
  factory SqlHighlightColors.fromScheme(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return SqlHighlightColors(
      keyword: scheme.primary,
      function: dark ? const Color(0xFFD7A6FF) : const Color(0xFF8A3FD1),
      string: dark ? const Color(0xFF9BD88A) : const Color(0xFF2F7D32),
      number: dark ? const Color(0xFFF5B66D) : const Color(0xFFB4560B),
      comment: scheme.onSurfaceVariant.withValues(alpha: 0.7),
      identifier: dark ? const Color(0xFF7CC7E8) : const Color(0xFF0B6A8F),
    );
  }

  /// Keywords such as `SELECT`.
  final Color keyword;

  /// Function names followed by `(`.
  final Color function;

  /// String literals.
  final Color string;

  /// Numeric literals.
  final Color number;

  /// Comments.
  final Color comment;

  /// Quoted identifiers.
  final Color identifier;
}

/// A [TextEditingController] that paints SQL with syntax highlighting.
class SqlEditingController extends TextEditingController {
  /// Creates a controller with optional initial [text].
  SqlEditingController({super.text});

  /// Palette; set by the editor widget from the active theme.
  SqlHighlightColors? colors;

  static final _token = RegExp(
    r'(--[^\n]*|/\*[\s\S]*?(?:\*/|$))' // 1 comment
    r"|('(?:[^']|'')*'?)" // 2 string
    r'|("(?:[^"]|"")*"?|`[^`]*`?|\[[^\]]*\]?)' // 3 quoted identifier
    r"|(\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b|\bX'[0-9A-Fa-f]*')" // 4 number/blob
    r'|([A-Za-z_][A-Za-z0-9_]*)(?=\s*\()' // 5 function call
    r'|([A-Za-z_][A-Za-z0-9_]*)', // 6 word
  );

  static final _keywords = {
    for (final k in SqlAutocomplete.keywords) ...k.split(' '),
    'PRIMARY',
    'KEY',
    'FOREIGN',
    'REFERENCES',
    'DEFAULT',
    'UNIQUE',
    'CHECK',
    'INTEGER',
    'TEXT',
    'REAL',
    'BLOB',
    'NUMERIC',
    'IF',
    'TEMP',
    'TRIGGER',
    'BEGIN',
    'COMMIT',
    'ROLLBACK',
    'TRANSACTION',
    'REPLACE',
    'IGNORE',
    'CONFLICT',
    'ABORT',
    'FAIL',
    'TRUE',
    'FALSE',
    'ALL',
    'ANY',
    'NATURAL',
    'OUTER',
    'RIGHT',
    'FULL',
    'OVER',
    'PARTITION',
    'WINDOW',
    'ROWID',
    'WITHOUT',
    'STRICT',
    'VIRTUAL',
    'GLOB',
    'REGEXP',
    'MATCH',
    'NOTNULL',
    'ISNULL',
    'AUTOINCREMENT',
    'QUERY',
    'PLAN',
    'ADD',
    'COLUMN',
    'RENAME',
    'TO',
    'VACUUM',
    'ANALYZE',
    'REINDEX',
    'ATTACH',
    'DETACH',
  };

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final c = colors;
    // Highlighting during IME composition would fight the composing
    // underline, so fall back to plain text there.
    if (c == null || (withComposing && value.composing.isValid)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in _token.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final t = m.group(0)!;
      final TextStyle? s;
      if (m.group(1) != null) {
        s = TextStyle(color: c.comment, fontStyle: FontStyle.italic);
      } else if (m.group(2) != null) {
        s = TextStyle(color: c.string);
      } else if (m.group(3) != null) {
        s = TextStyle(color: c.identifier);
      } else if (m.group(4) != null) {
        s = TextStyle(color: c.number);
      } else if (m.group(5) != null) {
        s = _keywords.contains(t.toUpperCase())
            ? TextStyle(color: c.keyword, fontWeight: FontWeight.w600)
            : TextStyle(color: c.function);
      } else if (_keywords.contains(t.toUpperCase())) {
        s = TextStyle(color: c.keyword, fontWeight: FontWeight.w600);
      } else {
        s = null;
      }
      spans.add(TextSpan(text: t, style: s));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return TextSpan(style: style, children: spans);
  }
}
