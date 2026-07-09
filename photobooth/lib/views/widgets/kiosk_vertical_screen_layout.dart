import 'package:flutter/material.dart';

import 'centered_max_width.dart';

/// POSE-anchored kiosk layout: always read **top → bottom**.
///
/// 1. Optional [chrome] — compact status (stepper, checklist) below the app bar
/// 2. [hero] — fills remaining space, centered (preview / portrait card)
/// 3. Optional [footer] — pinned actions / secondary content ([maxFooterWidth] 360)
class KioskVerticalScreenLayout extends StatelessWidget {
  const KioskVerticalScreenLayout({
    super.key,
    this.chrome,
    required this.hero,
    this.footer,
    this.heroMaxWidth = 720,
    this.maxFooterWidth = 360,
    this.maxFooterHeight = 200,
    this.footerScrollable = false,
    this.horizontalPadding = 16,
  });

  final Widget? chrome;
  final Widget hero;
  final Widget? footer;
  final double heroMaxWidth;
  final double maxFooterWidth;
  final double maxFooterHeight;
  final bool footerScrollable;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chrome != null) ...[
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: heroMaxWidth),
                child: chrome!,
              ),
            ),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: heroMaxWidth),
                child: hero,
              ),
            ),
          ),
          if (footer != null) ...[
            const SizedBox(height: 10),
            _buildFooter(),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final child = CenteredMaxWidth(
      maxWidth: maxFooterWidth,
      child: footer!,
    );
    if (!footerScrollable) {
      return child;
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxFooterHeight),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: child,
      ),
    );
  }
}

/// App-bar subtitle block matching POSE capture styling.
class KioskAppBarSubtitle extends StatelessWidget {
  const KioskAppBarSubtitle({
    super.key,
    required this.text,
    this.secondary,
  });

  final String text;
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 20, right: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
            textAlign: TextAlign.center,
          ),
          if (secondary != null && secondary!.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              secondary!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// Preferred height for a single-line [KioskAppBarSubtitle].
const double kKioskAppBarSubtitleHeight = 28;

/// Preferred height when app bar shows ready-state chrome (headline + badge).
const double kKioskAppBarReadyChromeHeight = 54;
