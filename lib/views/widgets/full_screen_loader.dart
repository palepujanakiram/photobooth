import 'package:flutter/cupertino.dart';

/// A reusable full-screen loader widget with customizable text and loader color
class FullScreenLoader extends StatelessWidget {
  final String text;
  final Color loaderColor;
  final Color? backgroundColor;
  final Color? textColor;

  const FullScreenLoader({
    super.key,
    required this.text,
    this.loaderColor = CupertinoColors.systemBlue,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor ?? CupertinoColors.black.withValues(alpha: 0.8),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CupertinoActivityIndicator(
              radius: 20,
              color: loaderColor,
            ),
            const SizedBox(height: 24),
            Text(
              text,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: textColor ?? CupertinoColors.white,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

