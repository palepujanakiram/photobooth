import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../services/protected_image_loader.dart';
import '../../services/staff_api_service.dart';
import '../../utils/app_strings.dart';
import '../../utils/secure_image_url.dart';
import '../../utils/transformation_run_id.dart';
import '../transformation_details/transformation_details_view.dart';

/// Opens a full-screen pinch/zoom preview for a staff payment thumbnail.
void staffPaymentShowImagePreview(
  BuildContext context, {
  required String imageUrl,
  String? sessionId,
  String? title,
  String? subtitle,
  String? transformationRunId,
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
        transformationRunId: transformationRunId,
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
    this.transformationRunId,
  });

  final String imageUrl;
  final String? sessionId;
  final String? title;
  final String? subtitle;
  final String? transformationRunId;

  @override
  State<StaffPaymentImagePreviewScreen> createState() =>
      _StaffPaymentImagePreviewScreenState();
}

class _StaffPaymentImagePreviewScreenState
    extends State<StaffPaymentImagePreviewScreen> {
  Uint8List? _bytes;
  bool _failed = false;
  String? _runId;

  @override
  void initState() {
    super.initState();
    final seeded = widget.transformationRunId?.trim();
    _runId = (seeded != null && seeded.isNotEmpty) ? seeded : null;
    _load();
  }

  Future<void> _load() async {
    final bytesFuture = staffPaymentLoadImageBytes(
      imageUrl: widget.imageUrl,
      sessionId: widget.sessionId,
    );
    final runFuture = _resolveRunId();
    final bytes = await bytesFuture;
    final runId = await runFuture;
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _failed = bytes == null;
      if (runId != null && runId.isNotEmpty) _runId = runId;
    });
  }

  Future<String?> _resolveRunId() async {
    if (_runId != null && _runId!.isNotEmpty) return _runId;
    final sid = widget.sessionId?.trim() ?? '';
    if (sid.isEmpty) return null;
    try {
      final api = StaffApiService();
      final session = await api.fetchSession(sid);
      final fromSession = transformationRunIdFromSessionMap(session);
      if (fromSession != null) return fromSession;
      final runs = await api.fetchSessionRuns(sid);
      return latestTransformationRunIdFromRunsResponse(runs);
    } catch (_) {
      return null;
    }
  }

  void _openTransformationDetails() {
    final runId = _runId?.trim();
    if (runId == null || runId.isEmpty) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TransformationDetailsScreen(
          runId: runId,
          fallbackSessionId: widget.sessionId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCaption = (widget.title?.isNotEmpty ?? false) ||
        (widget.subtitle?.isNotEmpty ?? false);
    final hasRun = _runId != null && _runId!.isNotEmpty;

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
                          padding: const EdgeInsets.only(top: 14, right: 8),
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
                      )
                    else
                      const Spacer(),
                    if (hasRun)
                      TextButton(
                        onPressed: _openTransformationDetails,
                        child: Text(
                          AppStrings.beholdTransformationDetailsLink,
                          style: TextStyle(
                            color: Colors.amber.shade200,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
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
    // Lock to print sheet aspect (1200×1800) so staff view matches look + DNP.
    return InteractiveViewer(
      minScale: 0.85,
      maxScale: 4,
      child: Center(
        child: AspectRatio(
          aspectRatio: 1200 / 1800,
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
  }
}
