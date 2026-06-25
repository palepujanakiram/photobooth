import 'package:flutter/material.dart';

import '../../views/widgets/cached_network_image.dart';

bool isSlideshowAssetImagePath(String path) {
  final p = path.trim().toLowerCase();
  return p.startsWith('assets/');
}

/// Full-bleed slideshow frame: bundled asset or remote theme sample URL.
class ThemeSlideshowImage extends StatelessWidget {
  const ThemeSlideshowImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
    this.errorWidget,
  });

  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? placeholder;
  final Widget? errorWidget;

  @override
  Widget build(BuildContext context) {
    if (isSlideshowAssetImagePath(path)) {
      return Image.asset(
        path,
        fit: fit,
        width: width,
        height: height,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) =>
            errorWidget ?? const _SlideshowImageFallback(),
      );
    }
    return CachedNetworkImage(
      imageUrl: path,
      fit: fit,
      width: width,
      height: height,
      placeholder: placeholder ??
          const ColoredBox(
            color: Colors.black,
            child: Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          ),
      errorWidget: errorWidget ?? const _SlideshowImageFallback(),
    );
  }
}

class _SlideshowImageFallback extends StatelessWidget {
  const _SlideshowImageFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Icon(Icons.image_not_supported, size: 64, color: Colors.white54),
      ),
    );
  }
}
