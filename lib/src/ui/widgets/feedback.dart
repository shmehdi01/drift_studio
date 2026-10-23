import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Copies [text] and confirms with a short snackbar.
Future<void> copyToClipboard(
  BuildContext context,
  String text, {
  String label = 'Copied',
}) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(label),
      behavior: SnackBarBehavior.floating,
      width: 280,
      duration: const Duration(milliseconds: 1400),
    ));
}

/// Shows an error in a snackbar.
void showStudioError(BuildContext context, Object error) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    content: Text('$error'),
    behavior: SnackBarBehavior.floating,
    backgroundColor: Theme.of(context).colorScheme.error,
  ));
}

/// Asks the user to confirm a destructive or writing action.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String? code,
  String confirmLabel = 'Run',
}) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: scheme.error),
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            if (code != null) ...[
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    code,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// A centered icon + message for empty and error states.
class StudioMessage extends StatelessWidget {
  /// Creates a message.
  const StudioMessage({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.isError = false,
  });

  /// Leading icon.
  final IconData icon;

  /// Headline.
  final String title;

  /// Optional detail text (selectable, for copying errors).
  final String? detail;

  /// Uses the error colour.
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        isError ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: color.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(title,
                style: theme.textTheme.titleSmall?.copyWith(color: color)),
            if (detail != null) ...[
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SelectableText(
                  detail!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
