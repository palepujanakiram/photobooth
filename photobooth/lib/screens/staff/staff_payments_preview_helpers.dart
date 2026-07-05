import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../services/protected_image_loader.dart';
import '../../utils/app_strings.dart';
import '../../utils/secure_image_url.dart';

/// Opens a full-screen pinch/zoom preview for a staff payment thumbnail.
void staffPaymentShowImagePreview(
  BuildContext context, {
  required String imageUrl,
  String? sessionId,
  String? title,
  String? subtitle,
}) {
  final url = imageUrl.trim();
  if (url.isEmpty) return;
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => StaffPaymentImagePreviewScreen(
        imageUrl: url,
        sessionId: sessionId,
        title: title,
        subtitle: subtitle,
      ),
    ),
  );
}

/// Loads staff-payment image bytes (protected URLs use [X-Staff-Token]).
Future<Uint8List?> staffPaymentLoadImageBytes({
  required String imageUrl,
  String? sessionId,
}) async {
  final resolved = imageUrl.trim();
  if (resolved.isEmpty) return null;

  if (resolved.startsWith(AppStrings.dataImagePrefix)) {
    try {
      return UriData.parse(resolved).contentAsBytes();
    } catch (_) {
      return null;
    }
  }

  final looksLikeBase64 = !resolved.startsWith('http') &&
      !resolved.startsWith('/') &&
      resolved.length > 100 &&
      resolved.length < 200000;
  if (looksLikeBase64) {
    try {
      return base64Decode(resolved);
    } catch (_) {
      return null;
    }
  }

  final secured = SecureImageUrl.withSessionId(
    SecureImageUrl.absolutize(resolved),
    sessionId: sessionId,
  );
  if (secured.isEmpty) return null;

  try {
    final loader = ProtectedImageLoader.instance;
    return ProtectedImageLoader.isProtectedUrl(secured)
        ? await loader.fetchBytesWithStaffAuth(secured)
        : await loader.fetchBytes(secured);
  } catch (_) {
    return null;
  }
}

class StaffPaymentImagePreviewScreen extends StatefulWidget {
  const StaffPaymentImagePreviewScreen({
    super.key,
    required this.imageUrl,
    this.sessionId,
    this.title,
    this.subtitle,
  });

  final String imageUrl;
  final String? sessionId;
  final String? title;
  final String? subtitle;

  @override
  State<StaffPaymentImagePreviewScreen> createState() =>
      _StaffPaymentImagePreviewScreenState();
}

class _StaffPaymentImagePreviewScreenState
    extends State<StaffPaymentImagePreviewScreen> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await staffPaymentLoadImageBytes(
      imageUrl: widget.imageUrl,
      sessionId: widget.sessionId,
    );
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _failed = bytes == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasCaption = (widget.title?.isNotEmpty ?? false) ||
        (widget.subtitle?.isNotEmpty ?? false);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: _buildBody()),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.72),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: 'Close',
                    ),
                    if (hasCaption)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 14, right: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.title?.isNotEmpty ?? false)
                                Text(
                                  widget.title!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (widget.subtitle?.isNotEmpty ?? false) ...[
                                const SizedBox(height: 2),
                                Text(
                                  widget.subtitle!,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.72),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_failed) {
      return const Center(
        child: Icon(
          CupertinoIcons.exclamationmark_triangle,
          color: Colors.white54,
          size: 48,
        ),
      );
    }
    final bytes = _bytes;
    if (bytes == null) {
      return const Center(
        child: SizedBox(
          width: 48,
          height: 48,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2,
          ),
        ),
      );
    }
    return InteractiveViewer(
      minScale: 0.85,
      maxScale: 4,
      child: Center(
        child: Image.memory(
          bytes,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}
