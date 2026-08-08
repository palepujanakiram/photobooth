import 'dart:async';
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

/// Opens a full-screen pinch/zoom preview for staff payment photo(s).
void staffPaymentShowImagePreview(
  BuildContext context, {
  required String imageUrl,
  List<String>? imageUrls,
  String? sessionId,
  String? title,
  String? subtitle,
  String? transformationRunId,
}) {
  final urls = <String>[];
  for (final u in imageUrls ?? const <String>[]) {
    final t = u.trim();
    if (t.isNotEmpty && !urls.contains(t)) urls.add(t);
  }
  final single = imageUrl.trim();
  if (single.isNotEmpty && !urls.contains(single)) {
    urls.insert(0, single);
  }
  if (urls.isEmpty) return;
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => StaffPaymentImagePreviewScreen(
        imageUrls: urls,
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
    required this.imageUrls,
    this.sessionId,
    this.title,
    this.subtitle,
    this.transformationRunId,
  });

  /// One or more session deliverables (strip, Surprise Me, AI looks, …).
  final List<String> imageUrls;
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
  final Map<int, Uint8List> _bytesByIndex = {};
  final Set<int> _failedIndexes = {};
  final Set<int> _loadingIndexes = {};
  String? _runId;
  int _pageIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    final seeded = widget.transformationRunId?.trim();
    _runId = (seeded != null && seeded.isNotEmpty) ? seeded : null;
    _pageController = PageController();
    _loadPage(0);
    unawaited(_resolveRunId().then((runId) {
      if (!mounted) return;
      if (runId != null && runId.isNotEmpty) {
        setState(() => _runId = runId);
      }
    }));
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadPage(int index) async {
    if (index < 0 || index >= widget.imageUrls.length) return;
    if (_bytesByIndex.containsKey(index) || _loadingIndexes.contains(index)) {
      return;
    }
    _loadingIndexes.add(index);
    final bytes = await staffPaymentLoadImageBytes(
      imageUrl: widget.imageUrls[index],
      sessionId: widget.sessionId,
    );
    if (!mounted) return;
    _loadingIndexes.remove(index);
    setState(() {
      if (bytes == null || bytes.isEmpty) {
        _failedIndexes.add(index);
      } else {
        _bytesByIndex[index] = bytes;
        _failedIndexes.remove(index);
      }
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

  void _goToPage(int index) {
    if (index < 0 || index >= widget.imageUrls.length) return;
    if (index == _pageIndex) return;
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasCaption = (widget.title?.isNotEmpty ?? false) ||
        (widget.subtitle?.isNotEmpty ?? false);
    final hasRun = _runId != null && _runId!.isNotEmpty;
    final multi = widget.imageUrls.length > 1;
    final pageCount = widget.imageUrls.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: PageView.builder(
                controller: _pageController,
                itemCount: pageCount,
                onPageChanged: (i) {
                  setState(() => _pageIndex = i);
                  unawaited(_loadPage(i));
                  if (i + 1 < pageCount) {
                    unawaited(_loadPage(i + 1));
                  }
                },
                itemBuilder: (_, i) => _buildPage(i),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _StaffPaymentPreviewTopBar(
                hasCaption: hasCaption,
                hasRun: hasRun,
                multi: multi,
                title: widget.title,
                subtitle: widget.subtitle,
                pageIndex: _pageIndex,
                pageCount: pageCount,
                onClose: () => Navigator.of(context).maybePop(),
                onOpenDetails:
                    hasRun ? _openTransformationDetails : null,
              ),
            ),
            if (multi) ...[
              Positioned(
                left: 4,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _StaffPaymentPreviewNavButton(
                    icon: CupertinoIcons.chevron_left,
                    tooltip: AppStrings.staffPreviewPreviousPhoto,
                    enabled: _pageIndex > 0,
                    onPressed: () => _goToPage(_pageIndex - 1),
                  ),
                ),
              ),
              Positioned(
                right: 4,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _StaffPaymentPreviewNavButton(
                    icon: CupertinoIcons.chevron_right,
                    tooltip: AppStrings.staffPreviewNextPhoto,
                    enabled: _pageIndex < pageCount - 1,
                    onPressed: () => _goToPage(_pageIndex + 1),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
                child: _StaffPaymentPreviewPageDots(
                  pageIndex: _pageIndex,
                  pageCount: pageCount,
                  onSelect: _goToPage,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPage(int index) {
    if (_failedIndexes.contains(index)) {
      return const Center(
        child: Icon(
          CupertinoIcons.exclamationmark_triangle,
          color: Colors.white54,
          size: 48,
        ),
      );
    }
    final bytes = _bytesByIndex[index];
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
    // Fresh viewer per page so pinch-zoom does not stick across photos.
    return InteractiveViewer(
      key: ValueKey<int>(index),
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

/// Top chrome for [StaffPaymentImagePreviewScreen] (keeps build under S3776).
class _StaffPaymentPreviewTopBar extends StatelessWidget {
  const _StaffPaymentPreviewTopBar({
    required this.hasCaption,
    required this.hasRun,
    required this.multi,
    required this.title,
    required this.subtitle,
    required this.pageIndex,
    required this.pageCount,
    required this.onClose,
    this.onOpenDetails,
  });

  final bool hasCaption;
  final bool hasRun;
  final bool multi;
  final String? title;
  final String? subtitle;
  final int pageIndex;
  final int pageCount;
  final VoidCallback onClose;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
            onPressed: onClose,
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
                    if (title?.isNotEmpty ?? false)
                      Text(
                        title!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (subtitle?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (multi) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${AppStrings.staffPrintPhotoN(pageIndex + 1)} / $pageCount',
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
          if (hasRun && onOpenDetails != null)
            TextButton(
              onPressed: onOpenDetails,
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
    );
  }
}

/// Large hit-target chevron so phones can change pages without relying on swipe.
class _StaffPaymentPreviewNavButton extends StatelessWidget {
  const _StaffPaymentPreviewNavButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: enabled ? 0.45 : 0.2),
      shape: const CircleBorder(),
      child: IconButton(
        iconSize: 28,
        padding: const EdgeInsets.all(12),
        tooltip: tooltip,
        onPressed: enabled ? onPressed : null,
        icon: Icon(
          icon,
          color: enabled ? Colors.white : Colors.white38,
        ),
      ),
    );
  }
}

/// Tappable page dots under multi-photo staff preview.
class _StaffPaymentPreviewPageDots extends StatelessWidget {
  const _StaffPaymentPreviewPageDots({
    required this.pageIndex,
    required this.pageCount,
    required this.onSelect,
  });

  final int pageIndex;
  final int pageCount;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < pageCount; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          GestureDetector(
            onTap: () => onSelect(i),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: i == pageIndex ? 10 : 8,
                height: i == pageIndex ? 10 : 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == pageIndex
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
