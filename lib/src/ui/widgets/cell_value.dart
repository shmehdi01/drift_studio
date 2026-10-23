import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../studio_theme.dart';

/// How a raw SQLite value is classified for display.
enum ValueKind {
  /// SQL NULL.
  nil,

  /// Integer or real.
  number,

  /// Text.
  text,

  /// Text that parses as a JSON object or array.
  json,

  /// Binary data.
  blob,
}

/// Classifies and formats SQLite values consistently across the studio.
abstract final class ValueFormat {
  /// Classifies [v].
  static ValueKind kindOf(Object? v) => switch (v) {
        null => ValueKind.nil,
        num() || BigInt() => ValueKind.number,
        Uint8List() => ValueKind.blob,
        final String s when _looksLikeJson(s) => ValueKind.json,
        _ => ValueKind.text,
      };

  /// One-line preview for grid cells.
  static String preview(Object? v) => switch (v) {
        null => 'NULL',
        final Uint8List b => 'BLOB · ${_bytes(b.length)}',
        final String s => s.replaceAll(RegExp(r'\s*\n\s*'), ' ⏎ '),
        _ => v.toString(),
      };

  /// Full, multi-line text for the row inspector.
  static String full(Object? v) => switch (v) {
        null => 'NULL',
        final Uint8List b => _hexDump(b),
        final String s when _looksLikeJson(s) => _prettyJson(s) ?? s,
        _ => v.toString(),
      };

  /// Interprets integers that look like Unix timestamps — Drift stores
  /// `DateTime` columns as seconds since epoch by default — and ISO-8601
  /// strings, returning a readable local time. Returns `null` otherwise.
  static String? asDateTime(Object? v, {String columnName = ''}) {
    DateTime? dt;
    if (v is int) {
      final hinted = RegExp(r'(date|time|_at$|At$|created|updated|expir)',
              caseSensitive: false)
          .hasMatch(columnName);
      // Seconds between 2001 and 2100, or milliseconds in the same range.
      if (v > 978307200 && v < 4102444800 && hinted) {
        dt = DateTime.fromMillisecondsSinceEpoch(v * 1000);
      } else if (v > 978307200000 && v < 4102444800000) {
        dt = DateTime.fromMillisecondsSinceEpoch(v);
      }
    } else if (v is String && v.length >= 10 && v.length <= 35) {
      if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(v)) dt = DateTime.tryParse(v);
    }
    if (dt == null) return null;
    final l = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} '
        '${two(l.hour)}:${two(l.minute)}:${two(l.second)} (local)';
  }

  static bool _looksLikeJson(String s) {
    final t = s.trimLeft();
    if (t.length < 2 || (t[0] != '{' && t[0] != '[')) return false;
    return _prettyJson(t) != null;
  }

  static String? _prettyJson(String s) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(s));
    } catch (_) {
      return null;
    }
  }

  static String _bytes(int n) => n < 1024
      ? '$n B'
      : n < 1048576
          ? '${(n / 1024).toStringAsFixed(1)} KB'
          : '${(n / 1048576).toStringAsFixed(1)} MB';

  static String _hexDump(Uint8List b) {
    final out = StringBuffer();
    final shown = b.length > 4096 ? b.sublist(0, 4096) : b;
    for (var i = 0; i < shown.length; i += 16) {
      final chunk = shown.sublist(i, (i + 16).clamp(0, shown.length));
      out
        ..write(i.toRadixString(16).padLeft(6, '0'))
        ..write('  ')
        ..write(chunk
            .map((e) => e.toRadixString(16).padLeft(2, '0'))
            .join(' ')
            .padRight(48))
        ..write(' ')
        ..writeln(String.fromCharCodes(
            chunk.map((c) => c >= 32 && c < 127 ? c : 46)));
    }
    if (b.length > shown.length) out.write('… ${_bytes(b.length)} total');
    return out.toString();
  }
}

/// Renders one value in a grid cell: NULL dimmed, numbers right-aligned,
/// JSON and blobs tagged.
class CellValue extends StatelessWidget {
  /// Creates a cell for [value].
  const CellValue(this.value, {super.key, this.numericColumn = false});

  /// The raw value.
  final Object? value;

  /// Right-aligns the cell even for NULLs, keeping number columns tidy.
  final bool numericColumn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kind = ValueFormat.kindOf(value);
    final style = switch (kind) {
      ValueKind.nil => monoStyle(context,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.55))
          .copyWith(fontStyle: FontStyle.italic),
      ValueKind.number => monoStyle(context, color: scheme.tertiary),
      ValueKind.blob => monoStyle(context, color: scheme.secondary),
      _ => monoStyle(context),
    };
    final text = Text(
      ValueFormat.preview(value),
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
    final alignRight = kind == ValueKind.number || numericColumn;
    if (kind != ValueKind.json) {
      return Align(
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: text,
      );
    }
    return Row(
      children: [
        _Tag(label: 'JSON', color: scheme.secondary),
        const SizedBox(width: 6),
        Expanded(child: text),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.4,
          ),
        ),
      );
}
