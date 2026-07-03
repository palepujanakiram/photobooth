import 'dart:io' if (dart.library.html) 'dart:html' as io;
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../services/image_cache_service.dart';
import '../../services/protected_image_loader.dart';
import '../../utils/logger.dart';
import '../../utils/secure_image_url.dart';

/// Widget that displays a network image with disk caching
/// Falls back to network image if cache fails
class CachedNetworkImage extends StatefulWidget {
  final String imageUrl;
  final BoxFit? fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final FilterQuality filterQuality;

  const CachedNetworkImage({
    super.key,
    required this.imageUrl,
    this.fit,
    this.placeholder,
    this.errorWidget,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.filterQuality = FilterQuality.low,
  });

  @override
  State<CachedNetworkImage> createState() => _CachedNetworkImageState();
}

class _CachedNetworkImageState extends State<CachedNetworkImage> {
  final ImageCacheService _cacheService = ImageCacheService();
  io.File? _cachedFile; // Only used on mobile platforms
  Uint8List? _protectedBytes;
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
      _protectedBytes = null;
    });

    try {
      final resolvedUrl = SecureImageUrl.absolutize(widget.imageUrl);
      final securedUrl = SecureImageUrl.withSessionId(resolvedUrl);

      if (ProtectedImageLoader.isProtectedUrl(resolvedUrl)) {
        final bytes = await ProtectedImageLoader.instance.fetchBytes(
          resolvedUrl,
        );
        if (mounted) {
          setState(() {
            _protectedBytes = bytes;
            _isLoading = false;
          });
        }
        return;
      }

      if (kIsWeb) {
        _finishLoading();
        return;
      }

      final cachedFile = await _cacheService.getCachedFile(securedUrl);
      if (await _tryUseCachedFile(cachedFile)) {
        return;
      }

      _finishLoading();
      _cacheInBackground(securedUrl);
    } catch (e) {
      AppLogger.debug('Error loading cached image: $e');
      if (!mounted) return;
      if (ProtectedImageLoader.isProtectedUrl(
        SecureImageUrl.absolutize(widget.imageUrl),
      )) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
        return;
      }
      _finishLoading();
    }
  }

  void _finishLoading() {
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<bool> _tryUseCachedFile(dynamic cachedFile) async {
    if (cachedFile == null || kIsWeb) return false;
    if (!await cachedFile.exists()) return false;
    if (!mounted) return false;
    setState(() {
      _cachedFile = cachedFile as dynamic;
      _isLoading = false;
    });
    return true;
  }

  void _cacheInBackground(String securedUrl) {
    _cacheService.cacheImage(securedUrl).then((cachedFile) {
      if (!mounted || cachedFile == null || kIsWeb) return;
      if (!cachedFile.existsSync()) return;
      setState(() => _cachedFile = cachedFile as dynamic);
    }).catchError((e) {
      AppLogger.debug('Background cache failed for $securedUrl: $e');
    });
  }

  Widget _defaultPlaceholder() {
    return widget.placeholder ??
        Container(
          color: Colors.transparent,
          child: const Center(child: CupertinoActivityIndicator()),
        );
  }

  Widget _defaultErrorWidget() {
    return widget.errorWidget ??
        const Icon(
          CupertinoIcons.photo,
          size: 64,
          color: CupertinoColors.systemGrey,
        );
  }

  Widget _buildNetworkImage(String securedUrl) {
    return Image.network(
      securedUrl,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
      filterQuality: widget.filterQuality,
      color: null,
      colorBlendMode: null,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _defaultPlaceholder();
      },
      errorBuilder: (context, error, stackTrace) => _defaultErrorWidget(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final securedUrl =
        SecureImageUrl.withSessionId(SecureImageUrl.absolutize(widget.imageUrl));
    if (_isLoading && widget.placeholder != null) {
      return widget.placeholder!;
    }

    if (_hasError && widget.errorWidget != null) {
      return widget.errorWidget!;
    }

    final protectedBytes = _protectedBytes;
    if (protectedBytes != null) {
      return Image.memory(
        protectedBytes,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        cacheWidth: widget.cacheWidth,
        cacheHeight: widget.cacheHeight,
        filterQuality: widget.filterQuality,
        errorBuilder: (context, error, stackTrace) =>
            _defaultErrorWidget(),
      );
    }

    if (!kIsWeb && _cachedFile != null) {
      final file = _cachedFile as dynamic;
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          cacheWidth: widget.cacheWidth,
          cacheHeight: widget.cacheHeight,
          filterQuality: widget.filterQuality,
          color: null,
          colorBlendMode: null,
          errorBuilder: (context, error, stackTrace) =>
              _buildNetworkImage(securedUrl),
        );
      }
    }

    return _buildNetworkImage(securedUrl);
  }
}
