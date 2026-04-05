import 'dart:math' as math;
import 'package:flutter/cupertino.dart';

/// Asset paths for slideshow: assets/slideshow/slideshow_1.png through slideshow_19.png.
final List<String> kSlideshowAssetPaths = [
  for (int i = 1; i <= 19; i++) 'assets/slideshow/slideshow_$i.png',
];

/// Transition type when changing the image in a card.
enum _TransitionType { flip, dissolve, scale, slide }

/// Animated slideshow background: a grid of image cards (e.g. 5 columns × 4 rows)
/// that stay in place. Each card cycles through images with random transitions
/// (flip, dissolve, scale, slide). Reusable on any screen—place in a Stack
/// behind your content.
class AnimatedSlideshowBackground extends StatefulWidget {
  /// Asset paths for slideshow images. If null, [kSlideshowAssetPaths] is used.
  final List<String>? assetPaths;

  /// Number of columns in the grid.
  final int gridColumns;

  /// Number of rows in the grid.
  final int gridRows;

  /// Horizontal spacing between cards.
  final double horizontalSpacing;

  /// Vertical spacing between cards.
  final double verticalSpacing;

  const AnimatedSlideshowBackground({
    super.key,
    this.assetPaths,
    this.gridColumns = 5,
    this.gridRows = 4,
    this.horizontalSpacing = 8.0,
    this.verticalSpacing = 8.0,
  });

  @override
  State<AnimatedSlideshowBackground> createState() =>
      _AnimatedSlideshowBackgroundState();
}

class _AnimatedSlideshowBackgroundState extends State<AnimatedSlideshowBackground> {
  late List<String> _paths;
  bool _precached = false;

  @override
  void initState() {
    super.initState();
    _paths = widget.assetPaths ?? List<String>.from(kSlideshowAssetPaths);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached && _paths.isNotEmpty) {
      _precached = true;
      for (final path in _paths) {
        precacheImage(AssetImage(path), context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_paths.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final cols = widget.gridColumns;
        final rows = widget.gridRows;
        final hSpacing = widget.horizontalSpacing;
        final vSpacing = widget.verticalSpacing;

        // Use floor so total height/width never exceed available space (avoids overflow)
        final totalVSpacing = (rows - 1) * vSpacing;
        final totalHSpacing = (cols - 1) * hSpacing;
        var cellHeight = (h - totalVSpacing) / rows;
        var cellWidth = (w - totalHSpacing) / cols;
        cellHeight = cellHeight.isFinite && cellHeight > 0
            ? cellHeight.floorToDouble()
            : 1.0;
        cellWidth =
            cellWidth.isFinite && cellWidth > 0 ? cellWidth.floorToDouble() : 1.0;

        return RepaintBoundary(
          child: ClipRect(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int row = 0; row < rows; row++) ...[
                  if (row > 0) SizedBox(height: vSpacing),
                  Row(
                    children: [
                      for (int col = 0; col < cols; col++) ...[
                        if (col > 0) SizedBox(width: hSpacing),
                        SizedBox(
                          width: cellWidth,
                          height: cellHeight,
                          child: _SlideshowCard(
                            assetPaths: _paths,
                            cellWidth: cellWidth,
                            cellHeight: cellHeight,
                            seed: row * cols + col,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A single card that stays in place and cycles through images with random
/// transitions (flip, dissolve, scale, slide).
class _SlideshowCard extends StatefulWidget {
  const _SlideshowCard({
    required this.assetPaths,
    required this.cellWidth,
    required this.cellHeight,
    required this.seed,
  });

  final List<String> assetPaths;
  final double cellWidth;
  final double cellHeight;
  final int seed;

  @override
  State<_SlideshowCard> createState() => _SlideshowCardState();
}

class _SlideshowCardState extends State<_SlideshowCard> {
  late math.Random _random;
  late int _currentIndex;
  late _TransitionType _transitionType;
  bool _slideFromTop = true; // for slide transition
  bool _schedulePending = false;

  @override
  void initState() {
    super.initState();
    _random = math.Random(widget.seed);
    _currentIndex = _random.nextInt(widget.assetPaths.length);
    _pickNextTransition();
    _scheduleNextChange();
  }

  void _pickNextTransition() {
    _transitionType =
        _TransitionType.values[_random.nextInt(_TransitionType.values.length)];
    _slideFromTop = _random.nextBool();
  }

  void _scheduleNextChange() {
    if (_schedulePending || !mounted || widget.assetPaths.length < 2) return;
    _schedulePending = true;
    final sec = 3 + _random.nextInt(6); // 3–8 seconds
    Future.delayed(Duration(seconds: sec), () {
      if (!mounted) return;
      _schedulePending = false;
      int nextIndex = _random.nextInt(widget.assetPaths.length);
      if (widget.assetPaths.length > 1) {
        while (nextIndex == _currentIndex) {
          nextIndex = _random.nextInt(widget.assetPaths.length);
        }
      }
      setState(() {
        _currentIndex = nextIndex;
        _pickNextTransition();
      });
      _scheduleNextChange();
    });
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.assetPaths[_currentIndex];
    return Container(
      width: widget.cellWidth,
      height: widget.cellHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return _buildTransition(animation, child);
        },
        child: _CardImage(
          key: ValueKey(path),
          assetPath: path,
          width: widget.cellWidth,
          height: widget.cellHeight,
        ),
      ),
    );
  }

  Widget _buildTransition(Animation<double> animation, Widget child) {
    switch (_transitionType) {
      case _TransitionType.flip:
        return _FlipTransition(animation: animation, child: child);
      case _TransitionType.dissolve:
        return FadeTransition(opacity: animation, child: child);
      case _TransitionType.scale:
        return ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOut),
          ),
          child: FadeTransition(opacity: animation, child: child),
        );
      case _TransitionType.slide:
        return SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0, _slideFromTop ? -0.15 : 0.15),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: FadeTransition(opacity: animation, child: child),
        );
    }
  }
}

/// 3D Y-axis flip transition (card flip).
class _FlipTransition extends StatelessWidget {
  const _FlipTransition({
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        const perspective = 0.001;
        final angle = math.pi * (1 - animation.value);
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, perspective)
          ..rotateY(angle);
        return Transform(
          alignment: Alignment.center,
          transform: matrix,
          child: child,
        );
      },
      child: child,
    );
  }
}

class _CardImage extends StatelessWidget {
  const _CardImage({
    super.key,
    required this.assetPath,
    required this.width,
    required this.height,
  });

  final String assetPath;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      fit: BoxFit.cover,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => Container(
        width: width,
        height: height,
        color: CupertinoColors.systemGrey5,
        child: Icon(
          CupertinoIcons.photo,
          color: CupertinoColors.systemGrey2,
          size: height * 0.4,
        ),
      ),
    );
  }
}
