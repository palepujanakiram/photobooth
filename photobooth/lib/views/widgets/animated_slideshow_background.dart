import 'dart:math' as math;
import 'package:flutter/cupertino.dart';

/// Asset paths for slideshow images.
/// Images 1–10 are JPG (resized to 512×512 for low GPU RAM); 11–18 are small PNGs; 19 is JPG.
final List<String> kSlideshowAssetPaths = [
  'assets/slideshow/slideshow_1.jpg',
  'assets/slideshow/slideshow_2.jpg',
  'assets/slideshow/slideshow_3.jpg',
  'assets/slideshow/slideshow_4.jpg',
  'assets/slideshow/slideshow_5.jpg',
  'assets/slideshow/slideshow_6.jpg',
  'assets/slideshow/slideshow_7.jpg',
  'assets/slideshow/slideshow_8.jpg',
  'assets/slideshow/slideshow_9.jpg',
  'assets/slideshow/slideshow_10.jpg',
  'assets/slideshow/slideshow_11.png',
  'assets/slideshow/slideshow_12.png',
  'assets/slideshow/slideshow_13.png',
  'assets/slideshow/slideshow_14.png',
  'assets/slideshow/slideshow_15.png',
  'assets/slideshow/slideshow_16.png',
  'assets/slideshow/slideshow_17.png',
  'assets/slideshow/slideshow_18.png',
  'assets/slideshow/slideshow_19.jpg',
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

  void _precacheSlideshowImages(BuildContext context) {
    for (final path in _paths) {
      if (_isNetworkImagePath(path)) {
        precacheImage(NetworkImage(path), context);
      } else {
        precacheImage(AssetImage(path), context);
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_precached && _paths.isNotEmpty) {
      _precached = true;
      _precacheSlideshowImages(context);
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

        if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
          return const SizedBox.shrink();
        }

        // Fill the viewport exactly with equal cells — no floored sizes (those left
        // gaps and made the grid feel misaligned). Spacing is fixed between tracks.
        return RepaintBoundary(
          child: ClipRect(
            child: SizedBox(
              width: w,
              height: h,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (int row = 0; row < rows; row++) ...[
                    if (row > 0) SizedBox(height: vSpacing),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (int col = 0; col < cols; col++) ...[
                            if (col > 0) SizedBox(width: hSpacing),
                            Expanded(
                              child: _SlideshowCard(
                                assetPaths: _paths,
                                seed: row * cols + col,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
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
    required this.seed,
  });

  final List<String> assetPaths;
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final cw = constraints.maxWidth;
        final ch = constraints.maxHeight;
        return Container(
          width: cw,
          height: ch,
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
              width: cw,
              height: ch,
            ),
          ),
        );
      },
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

bool _isNetworkImagePath(String path) {
  final p = path.trim().toLowerCase();
  return p.startsWith('http://') || p.startsWith('https://');
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
    // Decode budget: scale by device pixel ratio, cap for kiosk RAM. Use only
    // [cacheWidth] so aspect ratio is preserved in decode (setting both width
    // and height can produce visibly squashed theme samples on some backends).
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeW = (width * dpr).ceil().clamp(64, 2048);
    final placeholder = Container(
      width: width,
      height: height,
      color: CupertinoColors.systemGrey5,
      child: Icon(
        CupertinoIcons.photo,
        color: CupertinoColors.systemGrey2,
        size: math.min(width, height) * 0.4,
      ),
    );
    if (_isNetworkImagePath(assetPath)) {
      return Image.network(
        assetPath,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        width: width,
        height: height,
        cacheWidth: decodeW,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return placeholder;
        },
        errorBuilder: (_, __, ___) => placeholder,
      );
    }
    return Image.asset(
      assetPath,
      fit: BoxFit.cover,
      alignment: Alignment.center,
      width: width,
      height: height,
      cacheWidth: decodeW,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => placeholder,
    );
  }
}
