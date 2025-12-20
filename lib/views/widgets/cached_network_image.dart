import 'dart:io';
import 'package:flutter/cupertino.dart';
import '../../services/image_cache_service.dart';

/// Widget that displays a network image with disk caching
/// Falls back to network image if cache fails
class CachedNetworkImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit? fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final double? width;
  final double? height;

  const CachedNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
  });

  @override
  State<CachedNetworkImage> createState() => _CachedNetworkImageState();
}

class _CachedNetworkImageState extends State<CachedNetworkImage> {
  final ImageCacheService _cacheService = ImageCacheService();
  File? _cachedFile;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(CachedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _cachedFile = null;
    });

    try {
      // Try to get cached file first (fast check)
      final cachedFile = await _cacheService.getCachedFile(widget.imageUrl);
      
      if (cachedFile != null && await cachedFile.exists()) {
        if (mounted) {
          setState(() {
            _cachedFile = cachedFile;
            _isLoading = false;
          });
        }
        return;
      }

      // If not cached, show network image immediately
      // Cache in background for next time (non-blocking)
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      // Cache in background - don't block UI
      _cacheService.cacheImage(widget.imageUrl).then((cachedFile) {
        // If caching succeeded and we got a file, update state
        if (mounted && cachedFile != null && cachedFile.existsSync()) {
          setState(() {
            _cachedFile = cachedFile;
          });
        }
      }).catchError((e) {
        // Silently fail - network image will be shown
        debugPrint('Background cache failed for ${widget.imageUrl}: $e');
      });
    } catch (e) {
      debugPrint('Error loading cached image: $e');
      if (mounted) {
        setState(() {
          _hasError = false; // Don't show error, just use network
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && widget.placeholder != null) {
      return widget.placeholder!;
    }

    if (_hasError && widget.errorWidget != null) {
      return widget.errorWidget!;
    }

    // If we have a cached file, use it
    if (_cachedFile != null && _cachedFile!.existsSync()) {
      return Image.file(
        _cachedFile!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (context, error, stackTrace) {
          // If cached file fails, fall back to network
          return Image.network(
            widget.imageUrl,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return widget.placeholder ?? const Center(
                child: CupertinoActivityIndicator(),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return widget.errorWidget ?? const Icon(
                CupertinoIcons.photo,
                size: 64,
                color: CupertinoColors.systemGrey,
              );
            },
          );
        },
      );
    }

    // Fall back to network image
    return Image.network(
      widget.imageUrl,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return widget.placeholder ?? const Center(
          child: CupertinoActivityIndicator(),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return widget.errorWidget ?? const Icon(
          CupertinoIcons.photo,
          size: 64,
          color: CupertinoColors.systemGrey,
        );
      },
    );
  }
}

