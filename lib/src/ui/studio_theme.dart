import 'package:flutter/material.dart';

/// Monospace stack used for data and SQL; the first installed font wins.
const monoFamilyFallback = [
  'JetBrains Mono',
  'SF Mono',
  'Menlo',
  'Consolas',
  'Roboto Mono',
  'Courier New',
  'monospace',
];

/// Text style for monospaced content.
TextStyle monoStyle(BuildContext context, {double size = 12.5, Color? color}) =>
    TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: monoFamilyFallback,
      fontSize: size,
      height: 1.35,
      color: color ?? Theme.of(context).colorScheme.onSurface,
    );

/// Derives the studio's compact, data-dense theme from the host app theme so
/// it inherits the app's brand colour and light/dark mode.
ThemeData buildStudioTheme(ThemeData base) {
  final scheme = base.colorScheme;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: scheme.outlineVariant),
  );
  return base.copyWith(
    visualDensity: VisualDensity.compact,
    scaffoldBackgroundColor: scheme.surface,
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.6),
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: base.textTheme.labelMedium,
      side: BorderSide(color: scheme.outlineVariant),
    ),
    tooltipTheme: base.tooltipTheme.copyWith(
      waitDuration: const Duration(milliseconds: 400),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 12,
    ),
  );
}
