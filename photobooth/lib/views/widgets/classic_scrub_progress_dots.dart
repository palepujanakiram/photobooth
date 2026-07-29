import 'package:flutter/material.dart';

import '../../utils/classic_strip_scrub_coordinator.dart';

/// Yellow (in progress) / green (done) dots for Classic AF polish progress.
class ClassicScrubProgressDots extends StatelessWidget {
  const ClassicScrubProgressDots({
    super.key,
    required this.statuses,
    this.totalSlots,
  });

  final List<ClassicScrubDotStatus> statuses;

  /// When set (e.g. 4), shows empty slots ahead so guests see strip length.
  final int? totalSlots;

  @override
  Widget build(BuildContext context) {
    if (statuses.isEmpty && (totalSlots == null || totalSlots! <= 0)) {
      return const SizedBox.shrink();
    }
    final slots = totalSlots ?? statuses.length;
    return Semantics(
      label: 'Photo polish progress',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < slots; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            _Dot(
              status: i < statuses.length
                  ? statuses[i]
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.status});

  final ClassicScrubDotStatus? status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final double size;
    switch (status) {
      case ClassicScrubDotStatus.cleaned:
        color = const Color(0xFF3DDC97);
        size = 12;
      case ClassicScrubDotStatus.scrubbing:
        color = const Color(0xFFFFC107);
        size = 12;
      case ClassicScrubDotStatus.pending:
        color = const Color(0xFFFFC107).withValues(alpha: 0.55);
        size = 10;
      case ClassicScrubDotStatus.failed:
        color = const Color(0xFFFF8A3D);
        size = 12;
      case null:
        color = Colors.white24;
        size = 8;
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: status == ClassicScrubDotStatus.scrubbing
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.55),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}
