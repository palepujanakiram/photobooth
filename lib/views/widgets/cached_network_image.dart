import 'dart:io' if (dart.library.html) 'dart:html' as io;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
  io.File? _cachedFile; // Only used on mobile platforms
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
      // On web, skip file caching and use network image directly
      if (kIsWeb) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // Try to get cached file first (fast check) - mobile only
      // Note: getCachedFile returns dart:io.File, but we need to handle it carefully
      final cachedFile = await _cacheService.getCachedFile(widget.imageUrl);
      
      if (cachedFile != null && !kIsWeb) {
        // On mobile, check if file exists
        // cachedFile is dart:io.File from the service
        if (await cachedFile.exists()) {
          if (mounted) {
            setState(() {
              // Store as dynamic to avoid type conflicts between dart:io and dart:html
              _cachedFile = cachedFile as dynamic;
              _isLoading = false;
            });
          }
          return;
        }
      }

      // If not cached, show network image immediately
      // Cache in background for next time (non-blocking)
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      // Cache in background - don't block UI (mobile only)
      if (!kIsWeb) {
        _cacheService.cacheImage(widget.imageUrl).then((cachedFile) {
          // If caching succeeded and we got a file, update state
          if (mounted && cachedFile != null && !kIsWeb) {
            // cachedFile is dart:io.File from the service
            if (cachedFile.existsSync()) {
              setState(() {
                // Store as dynamic to avoid type conflicts between dart:io and dart:html
                _cachedFile = cachedFile as dynamic;
              });
            }
          }
        }).catchError((e) {
          // Silently fail - network image will be shown
          debugPrint('Background cache failed for ${widget.imageUrl}: $e');
        });
      }
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

    // If we have a cached file, use it (mobile only)
    if (!kIsWeb && _cachedFile != null) {
      // _cachedFile is stored as dynamic to avoid type conflicts
      // On mobile, it's actually dart:io.File
      final file = _cachedFile as dynamic;
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          color: null, // Ensure no color tint
          colorBlendMode: null, // Ensure no color blending
          errorBuilder: (context, error, stackTrace) {
            // If cached file fails, fall back to network
            return Image.network(
              widget.imageUrl,
              fit: widget.fit,
              width: widget.width,
              height: widget.height,
              color: null,
              colorBlendMode: null,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return widget.placeholder ?? Container(
                  color: Colors.transparent,
                  child: const Center(
                    child: CupertinoActivityIndicator(),
                  ),
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
    }

    // Fall back to network image
    return Image.network(
      widget.imageUrl,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      color: null, // Ensure no color tint
      colorBlendMode: null, // Ensure no color blending
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return widget.placeholder ?? Container(
          color: Colors.transparent,
          child: const Center(
            child: CupertinoActivityIndicator(),
          ),
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

