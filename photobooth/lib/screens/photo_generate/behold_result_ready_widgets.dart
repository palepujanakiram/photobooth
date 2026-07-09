import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/app_strings.dart';
import 'photo_generate_behold_aspect.dart';

/// Purple accent used for the ready-state hero glow and primary CTA.
const Color kBeholdReadyAccent = Color(0xFF8B5CF6);

const Color kBeholdReadyAccentDeep = Color(0xFF6D28D9);

/// App bar chrome on BEHOLD ready: headline under the title.
class BeholdReadyCompactAppBarChrome extends StatelessWidget {
  const BeholdReadyCompactAppBarChrome({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppStrings.beholdReadyTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          SizedBox(height: 4),
          Text(
            AppStrings.beholdReadySubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white70,
              fontWeight: FontWeight.w400,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

/// Mockup-style card: icon, headline, and Continue — sits to the right of the hero.
class BeholdReadyCelebrationPanel extends StatelessWidget {
  const BeholdReadyCelebrationPanel({
    super.key,
    required this.continueButton,
  });

  final Widget continueButton;

  @override
  Widget build(BuildContext context) {
    return BeholdReadyCelebrationCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: BeholdReadyCelebrationIcon()),
          const SizedBox(height: 20),
          continueButton,
        ],
      ),
    );
  }
}

/// Dark glass card matching the BEHOLD ready mockup.
class BeholdReadyCelebrationCard extends StatelessWidget {
  const BeholdReadyCelebrationCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF141B33).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: kBeholdReadyAccent.withValues(alpha: 0.28),
        ),
        boxShadow: [
          BoxShadow(
            color: kBeholdReadyAccent.withValues(alpha: 0.14),
            blurRadius: 28,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
        child: child,
      ),
    );
  }
}

/// Party-popper badge from the ready-state mockup.
class BeholdReadyCelebrationIcon extends StatelessWidget {
  const BeholdReadyCelebrationIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kBeholdReadyAccent.withValues(alpha: 0.14),
        border: Border.all(
          color: kBeholdReadyAccent.withValues(alpha: 0.55),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: kBeholdReadyAccent.withValues(alpha: 0.22),
            blurRadius: 16,
          ),
        ],
      ),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Icon(
          Icons.celebration_outlined,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }
}

/// Gradient scrim behind bottom-docked actions so the photo can extend underneath.
class BeholdReadyActionDock extends StatelessWidget {
  const BeholdReadyActionDock({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.5),
            Colors.black.withValues(alpha: 0.9),
          ],
          stops: const [0.0, 0.4, 1.0],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: child,
        ),
      ),
    );
  }
}

/// Side rail for landscape kiosks — actions beside the hero instead of below it.
class BeholdReadySidePanel extends StatelessWidget {
  const BeholdReadySidePanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
        child: child,
      ),
    );
  }
}

/// Full success copy for the app bar when the hero does not own the full screen.
class BeholdReadyAppBarChrome extends StatelessWidget {
  const BeholdReadyAppBarChrome({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppStrings.beholdReadyTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.white,
              fontWeight: FontWeight.w700,
              height: 1.15,
            ),
          ),
          SizedBox(height: 4),
          Text(
            AppStrings.beholdReadySubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Colors.white70,
              fontWeight: FontWeight.w400,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}

/// Success headline block shown in-body when app bar chrome is not used.
class BeholdReadySuccessHeader extends StatelessWidget {
  const BeholdReadySuccessHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            AppStrings.beholdReadyTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              color: Colors.white,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.beholdReadySubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.72),
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// Shield + privacy line for the secondary strip under the hero photo.
class BeholdReadyPrivacyFooter extends StatelessWidget {
  const BeholdReadyPrivacyFooter({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          CupertinoIcons.lock_shield_fill,
          size: compact ? 12 : 13,
          color: Colors.white.withValues(alpha: 0.45),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            compact
                ? AppStrings.generationWaitPrivacyFooter
                : AppStrings.beholdReadyPrivacyFooter,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: compact ? 10 : 11,
            ),
            maxLines: compact ? 1 : 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Gradient primary button for the kiosk Continue action on the ready screen.
class BeholdReadyContinueButton extends StatelessWidget {
  const BeholdReadyContinueButton({
    super.key,
    required this.label,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final decoration = enabled
        ? const BoxDecoration(
            gradient: LinearGradient(
              colors: [kBeholdReadyAccent, Color(0xFF3B82F6)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.all(Radius.circular(14)),
            boxShadow: [
              BoxShadow(
                color: Color(0x558B5CF6),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          )
        : BoxDecoration(
            color: CupertinoColors.systemGrey,
            borderRadius: BorderRadius.circular(14),
          );

    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: decoration,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onPressed : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: enabled ? 1 : 0.5),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }
}

/// Centers portrait art on a landscape 6×4 print-preview card with side mats.
Widget buildBeholdLandscapePrintMatHero({
  required double cardWidth,
  required double cardHeight,
  required double contentAspect,
  required Widget Function(double photoWidth, double photoHeight) buildPhoto,
}) {
  final photo = beholdLandscapePrintMatPhotoSize(
    cardWidth: cardWidth,
    cardHeight: cardHeight,
    contentAspect: contentAspect,
  );
  return ColoredBox(
    color: Colors.black,
    child: Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 10,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            width: photo.width,
            height: photo.height,
            child: buildPhoto(photo.width, photo.height),
          ),
        ),
      ),
    ),
  );
}

BoxDecoration beholdReadyHeroFrameDecoration({
  required bool selected,
  required bool emphasizeGlow,
}) {
  if (!emphasizeGlow) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: selected
            ? CupertinoColors.systemBlue.withValues(alpha: 0.85)
            : const Color(0xFF4A4A4A),
        width: selected ? 2.0 : 1.5,
      ),
    );
  }

  return BoxDecoration(
    borderRadius: BorderRadius.circular(14),
    border: Border.all(
      color: kBeholdReadyAccent.withValues(alpha: selected ? 0.9 : 0.45),
      width: 2,
    ),
    boxShadow: [
      BoxShadow(
        color: kBeholdReadyAccent.withValues(alpha: selected ? 0.42 : 0.22),
        blurRadius: 22,
        spreadRadius: 1,
      ),
      BoxShadow(
        color: kBeholdReadyAccentDeep.withValues(alpha: 0.18),
        blurRadius: 36,
        spreadRadius: 2,
      ),
    ],
  );
}
