import 'package:flutter/cupertino.dart';

/// Common snackbar widget for API errors and other messages
class AppSnackBar {
  /// Shows an error snackbar with consistent styling
  static void showError(BuildContext context, String message) {
    // Use Cupertino-style overlay for error messages
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => CupertinoAlertDialog(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.exclamationmark_triangle_fill,
              color: CupertinoColors.systemRed,
              size: 24,
            ),
            SizedBox(width: 8),
            Text('Error'),
          ],
        ),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// Shows a success snackbar
  static void showSuccess(BuildContext context, String message) {
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => CupertinoAlertDialog(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.checkmark_circle_fill,
              color: CupertinoColors.systemGreen,
              size: 24,
            ),
            SizedBox(width: 8),
            Text('Success'),
          ],
        ),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// Shows an info snackbar
  static void showInfo(BuildContext context, String message) {
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => CupertinoAlertDialog(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.info_circle_fill,
              color: CupertinoColors.systemBlue,
              size: 24,
            ),
            SizedBox(width: 8),
            Text('Info'),
          ],
        ),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            child: const Text('OK'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

