import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import 'cached_network_image.dart';

/// Full-screen preview for a generated portrait (pinch / pan via [InteractiveViewer]).
class GeneratedImagePreviewScreen extends StatelessWidget {
  const GeneratedImagePreviewScreen({
    super.key,
    required this.imageUrl,
    this.title,
    this.subtitle,
  });

  final String imageUrl;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final hasCaption = (title != null && title!.isNotEmpty) ||
        (subtitle != null && subtitle!.isNotEmpty);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: LayoutBuilder(
              builder: (context, constraints) {
                return InteractiveViewer(
                  minScale: 0.85,
                  maxScale: 4,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        placeholder: const SizedBox(
                          width: 48,
                          height: 48,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        errorWidget: const Icon(
                          CupertinoIcons.exclamationmark_triangle,
                          color: Colors.white54,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.72),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: 'Close',
                    ),
                    if (hasCaption)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 14, right: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (title != null && title!.isNotEmpty)
                                Text(
                                  title!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (subtitle != null && subtitle!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle!,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
