import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Copies [text] to the system clipboard and shows brief feedback.
Future<void> copyDebugPanelText(
  BuildContext context,
  String text, {
  String feedback = 'Copied to clipboard',
}) async {
  final trimmed = text.trim();
  if (trimmed.isEmpty || trimmed.startsWith('—')) return;

  await Clipboard.setData(ClipboardData(text: trimmed));
  if (!context.mounted) return;

  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(
      content: Text(feedback),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
