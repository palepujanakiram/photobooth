import 'dart:async';

import 'package:flutter/material.dart';

import '../../utils/app_strings.dart';
import '../../screens/photo_capture/photo_capture_flashback_auto_helpers.dart';

/// Classic between-shot review banner with a self-contained countdown.
///
/// Parent rebuild storms (camera / scrub notify) must not freeze the number —
/// this State owns a [Timer] and derives seconds from a fixed [endsAt].
class FlashbackReviewHoldBanner extends StatefulWidget {
  const FlashbackReviewHoldBanner({
    super.key,
    required this.endsAt,
    required this.isLastShot,
  });

  /// Absolute deadline when auto-accept should fire (set once per still).
  final DateTime endsAt;

  final bool isLastShot;

  @override
  State<FlashbackReviewHoldBanner> createState() =>
      _FlashbackReviewHoldBannerState();
}

class _FlashbackReviewHoldBannerState extends State<FlashbackReviewHoldBanner> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _armTick();
  }

  @override
  void didUpdateWidget(covariant FlashbackReviewHoldBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endsAt != widget.endsAt) {
      _armTick();
    }
  }

  void _armTick() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!mounted) return;
      setState(() {});
      if (!DateTime.now().isBefore(widget.endsAt)) {
        _tick?.cancel();
        _tick = null;
      }
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _tick = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secondsLeft = flashbackReviewSecondsRemaining(endsAt: widget.endsAt);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        AppStrings.flashbackReviewHoldStatus(
          isLastShot: widget.isLastShot,
          secondsLeft: secondsLeft,
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }
}
