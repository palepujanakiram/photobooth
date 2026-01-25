import 'package:flutter/cupertino.dart';

/// A reusable full-screen loader widget with customizable text and loader color
class FullScreenLoader extends StatelessWidget {
  final String text;
  final Color loaderColor;
  final Color? backgroundColor;
  final Color? textColor;
  final int? elapsedSeconds;
  final String? subtitle;
  final String? currentProcess;
  final String? hint;

  const FullScreenLoader({
    super.key,
    required this.text,
    this.loaderColor = CupertinoColors.systemBlue,
    this.backgroundColor,
    this.textColor,
    this.elapsedSeconds,
    this.subtitle,
    this.currentProcess,
    this.hint,
  });

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (minutes > 0) {
      return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
    }
    return '${seconds}s';
  }

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
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 14,
                  color: (textColor ?? CupertinoColors.white).withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (elapsedSeconds != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.timer,
                      color: CupertinoColors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(elapsedSeconds!),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: CupertinoColors.white,
                        fontFeatures: [
                          // Use tabular numbers for consistent width
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Current process indicator
            if (currentProcess != null && currentProcess!.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                margin: const EdgeInsets.symmetric(horizontal: 32),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemBlue.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: CupertinoColors.systemBlue.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CupertinoActivityIndicator(
                        radius: 8,
                        color: CupertinoColors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        currentProcess!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: CupertinoColors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // Hint at the bottom
            if (hint != null && hint!.isNotEmpty) ...[
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  hint!,
                  style: TextStyle(
                    fontSize: 13,
                    color: (textColor ?? CupertinoColors.white).withValues(alpha: 0.6),
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
}

