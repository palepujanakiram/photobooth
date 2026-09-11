import 'dart:io';

import 'package:flutter/material.dart';

/// Full-size view of one stored image, with pinch-to-zoom.
///
/// Shared by the item detail renditions and the settings frame preview: both
/// answer the same question — "is this actually the right picture" — and an
/// operator checking a frame before an event should not have to send one
/// through the printer to find out.
///
/// Opened as a dialog rather than a route so it dismisses with a tap and never
/// becomes somewhere you can get lost.
class EventImageViewer extends StatelessWidget {
  const EventImageViewer({
    super.key,
    required this.file,
    required this.title,
    this.subtitle,
  });

  final File file;
  final String title;
  final String? subtitle;

  static Future<void> show(
    BuildContext context, {
    required File file,
    required String title,
    String? subtitle,
  }) {
    return showDialog<void>(
      context: context,
      // Frames are mostly transparent artwork, so a plain black ground is the
      // only way to see what the border actually looks like.
      barrierColor: Colors.black87,
      builder: (_) => EventImageViewer(
        file: file,
        title: title,
        subtitle: subtitle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            Expanded(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                    // Full size here on purpose — this is the one screen whose
                    // whole job is showing the real picture. It is a single
                    // image on a screen the operator opened deliberately, not
                    // a grid of them.
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const Text(
                      'This image is no longer on the device.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
