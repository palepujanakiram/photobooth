import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/secure_image_url.dart';
import '../../views/widgets/cached_network_image.dart';

/// Cinematic flash → shimmer → scale reveal before navigating to BEHOLD.
class GenerationRevealOverlay extends StatefulWidget {
  const GenerationRevealOverlay({
    super.key,
    required this.imageUrl,
    required this.themeName,
    required this.onComplete,
  });

  final String imageUrl;
  final String themeName;
  final VoidCallback onComplete;

  @override
  State<GenerationRevealOverlay> createState() =>
      _GenerationRevealOverlayState();
}

class _GenerationRevealOverlayState extends State<GenerationRevealOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _hapticFired = false;

  static const _duration = Duration(milliseconds: 2800);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _duration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          widget.onComplete();
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(_controller.value);
        if (t > 0.55 && !_hapticFired) {
          _hapticFired = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            HapticFeedback.mediumImpact();
            SystemSound.play(SystemSoundType.click);
          });
        }

        final dim = (t * 1.4).clamp(0.0, 0.72);
        final shimmer = math.sin(t * math.pi * 3) * 0.35 + 0.15;
        final scale = 0.72 + Curves.easeOutBack.transform(((t - 0.25) / 0.75).clamp(0.0, 1.0)) * 0.28;
        final glow = ((t - 0.5) / 0.5).clamp(0.0, 1.0);

        final secureUrl = SecureImageUrl.withSessionId(widget.imageUrl);

        return Material(
          color: Colors.black.withValues(alpha: dim),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Transform.scale(
                  scale: scale,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF8B5CF6)
                              .withValues(alpha: 0.25 + glow * 0.45),
                          blurRadius: 28 + glow * 24,
                          spreadRadius: glow * 4,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        width: math.min(MediaQuery.sizeOf(context).width * 0.78, 420),
                        height: math.min(MediaQuery.sizeOf(context).width * 0.78, 420),
                        child: secureUrl.isEmpty
                            ? const ColoredBox(color: Colors.black)
                            : CachedNetworkImage(
                                imageUrl: secureUrl,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.medium,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(-1 + t * 2.2, -0.8),
                        end: Alignment(1 - t * 2.2, 0.8),
                        colors: [
                          Colors.transparent,
                          Colors.white.withValues(alpha: shimmer * t),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (t > 0.7)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.paddingOf(context).bottom + 48,
                  child: Opacity(
                    opacity: ((t - 0.7) / 0.3).clamp(0.0, 1.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Your masterpiece is ready!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 22,
                          ),
                        ),
                        if (widget.themeName.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.themeName.trim(),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.75),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Subtle entrance fade/scale on BEHOLD after the progress-route reveal.
class BeholdReadyEntrance extends StatefulWidget {
  const BeholdReadyEntrance({
    super.key,
    required this.child,
    required this.play,
  });

  final Widget child;
  final bool play;

  @override
  State<BeholdReadyEntrance> createState() => _BeholdReadyEntranceState();
}

class _BeholdReadyEntranceState extends State<BeholdReadyEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _scale = Tween<double>(begin: 0.96, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    if (widget.play) {
      _controller.value = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(BeholdReadyEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.play && !oldWidget.play) {
      _controller.forward(from: 0);
    } else if (!widget.play) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.play) return widget.child;
    return ScaleTransition(
      scale: _scale,
      child: widget.child,
    );
  }
}
