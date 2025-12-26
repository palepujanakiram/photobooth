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
      builder: (context) => _AnimatedErrorDialog(message: message),
    );
  }
}

/// Animated error dialog widget
class _AnimatedErrorDialog extends StatefulWidget {
  final String message;

  const _AnimatedErrorDialog({required this.message});

  @override
  State<_AnimatedErrorDialog> createState() => _AnimatedErrorDialogState();
}

class _AnimatedErrorDialogState extends State<_AnimatedErrorDialog>
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
