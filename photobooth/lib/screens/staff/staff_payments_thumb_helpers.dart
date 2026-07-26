import 'dart:typed_data';

import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/protected_image_loader.dart';
import '../../utils/app_strings.dart';
import '../../utils/secure_image_url.dart';
import 'staff_payments_payload_utils.dart';

/// Thumbnail rendering for staff payment rows (Sonar S3776 extraction).
Widget staffPaymentThumbImage({
  required String resolved,
  String? sessionId,
  required Widget Function() placeholder,
  Widget Function()? unavailable,
}) {
  if (resolved.isEmpty) return placeholder();
  final onUnavailable = unavailable ?? staffPaymentThumbUnavailable;

  if (resolved.startsWith(AppStrings.dataImagePrefix)) {
    return _staffPaymentDataUrlThumb(resolved, onUnavailable);
  }

  final looksLikeBase64 = !resolved.startsWith('http') &&
      !resolved.startsWith('/') &&
      resolved.length > 100 &&
      resolved.length < 200000;
  if (looksLikeBase64) {
    final fromB64 = _staffPaymentBase64Thumb(resolved, onUnavailable);
    if (fromB64 != null) return fromB64;
  }

  return StaffPaymentThumbNetworkImage(
    imageUrl: resolved,
    sessionId: sessionId ?? _sessionIdFromResolved(resolved),
    loadingPlaceholder: placeholder,
    unavailable: onUnavailable,
  );
}

String? _sessionIdFromResolved(String url) {
  final uri = Uri.tryParse(url);
  final sid = uri?.queryParameters['sessionId']?.trim();
  return (sid == null || sid.isEmpty) ? null : sid;
}

bool _looksLikeSvg(Uint8List bytes) {
  final head = String.fromCharCodes(
    bytes.take(bytes.length < 64 ? bytes.length : 64),
  ).trimLeft().toLowerCase();
  return head.startsWith('<svg') || head.startsWith('<?xml');
}

class StaffPaymentThumbNetworkImage extends StatefulWidget {
  const StaffPaymentThumbNetworkImage({
    super.key,
    required this.imageUrl,
    this.sessionId,
    required this.loadingPlaceholder,
    required this.unavailable,
  });

  final String imageUrl;
  final String? sessionId;
  final Widget Function() loadingPlaceholder;
  final Widget Function() unavailable;

  @override
  State<StaffPaymentThumbNetworkImage> createState() =>
      _StaffPaymentThumbNetworkImageState();
}

class _StaffPaymentThumbNetworkImageState
    extends State<StaffPaymentThumbNetworkImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(StaffPaymentThumbNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _bytes = null;
      _failed = false;
    });

    final resolved = SecureImageUrl.withSessionId(
      SecureImageUrl.absolutize(widget.imageUrl.trim()),
      sessionId: widget.sessionId,
    );
    if (resolved.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }

    try {
      final loader = ProtectedImageLoader.instance;
      final bytes = ProtectedImageLoader.isProtectedUrl(resolved)
          ? await loader.fetchBytesWithStaffAuth(resolved)
          : await loader.fetchBytes(resolved);
      if (!mounted) return;
      // Staff /api/img 404s return an SVG "Archived" placeholder — show tile, not decode.
      if (bytes.isEmpty || _looksLikeSvg(bytes)) {
        setState(() => _failed = true);
        return;
      }
      setState(() => _bytes = bytes);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return widget.unavailable();
    final bytes = _bytes;
    if (bytes == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 54,
          height: 54,
          child: widget.loadingPlaceholder(),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.memory(
        bytes,
        width: 54,
        height: 54,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => widget.unavailable(),
      ),
    );
  }
}

Widget _staffPaymentDataUrlThumb(
  String resolved,
  Widget Function() placeholder,
) {
  try {
    final uriData = UriData.parse(resolved);
    final bytes = uriData.contentAsBytes();
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.memory(
        bytes,
        width: 54,
        height: 54,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder(),
      ),
    );
  } catch (_) {
    return placeholder();
  }
}

Widget? _staffPaymentBase64Thumb(
  String resolved,
  Widget Function() placeholder,
) {
  try {
    final bytes = base64Decode(resolved);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.memory(
        bytes,
        width: 54,
        height: 54,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => placeholder(),
      ),
    );
  } catch (_) {
    return null;
  }
}

/// No photo URL yet (payment before capture/compose).
Widget staffPaymentThumbPlaceholder() {
  return Container(
    width: 54,
    height: 54,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.black12),
    ),
    alignment: Alignment.center,
    child: const Icon(Icons.image, size: 22, color: Colors.black45),
  );
}

/// URL exists but storage returned 404 / object cleaned up overnight.
Widget staffPaymentThumbUnavailable() {
  return Container(
    width: 54,
    height: 54,
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: const Color(0xFFF59E0B),
        style: BorderStyle.solid,
      ),
    ),
    alignment: Alignment.center,
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.broken_image_outlined, size: 18, color: Color(0xFFB45309)),
        SizedBox(height: 2),
        Text(
          'Archived',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w600,
            color: Color(0xFF92400E),
            height: 1,
          ),
        ),
      ],
    ),
  );
}

String staffPaymentThumbResolvedUrl({
  required String sessionId,
  required String payloadUrl,
  required Map<String, String> sessionThumbUrlCache,
}) {
  final sid = sessionId.trim();
  final raw = payloadUrl.trim().isNotEmpty
      ? payloadUrl.trim()
      : (sessionThumbUrlCache[sid] ?? '');
  return StaffPaymentsPayloadUtils.normalizeImageUrl(
    raw,
    sessionId: sid.isEmpty ? null : sid,
  );
}
