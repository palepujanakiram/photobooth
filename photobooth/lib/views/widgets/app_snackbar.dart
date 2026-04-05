import 'package:flutter/cupertino.dart';

/// Common snackbar widget for API errors and other messages
class AppSnackBar {
  /// Shows an animated error snackbar with consistent styling
  static void showError(BuildContext context, String message) {
    // Use animated overlay for error messages
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: CupertinoColors.black.withValues(alpha: 0.5),
      builder: (context) => _AnimatedMessageDialog(
        message: message,
        isError: true,
      ),
    );
  }

  /// Shows an animated success snackbar with consistent styling
  static void showSuccess(BuildContext context, String message) {
    // Use animated overlay for success messages
    showCupertinoDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: CupertinoColors.black.withValues(alpha: 0.5),
      builder: (context) => _AnimatedMessageDialog(
        message: message,
        isError: false,
      ),
    );
  }
}

/// Animated message dialog widget (for both error and success)
class _AnimatedMessageDialog extends StatefulWidget {
  final String message;
  final bool isError;

  const _AnimatedMessageDialog({
    required this.message,
    required this.isError,
  });

  @override
  State<_AnimatedMessageDialog> createState() => _AnimatedMessageDialogState();
}

class _AnimatedMessageDialogState extends State<_AnimatedMessageDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    ));

    // Start animation
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacityAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: CupertinoAlertDialog(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isError
                    ? CupertinoIcons.exclamationmark_triangle_fill
                    : CupertinoIcons.checkmark_circle_fill,
                color: widget.isError
                    ? CupertinoColors.systemRed
                    : CupertinoColors.systemGreen,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(widget.isError ? 'Error' : 'Success'),
            ],
          ),
          content: Text(widget.message),
          actions: [
            CupertinoDialogAction(
              child: const Text('OK'),
              onPressed: () {
                _controller.reverse().then((_) {
                  Navigator.of(context).pop();
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
