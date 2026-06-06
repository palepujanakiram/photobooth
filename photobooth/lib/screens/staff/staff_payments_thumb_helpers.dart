import 'dart:convert';

import 'package:flutter/material.dart';

import '../../utils/app_strings.dart';
import 'staff_payments_payload_utils.dart';

/// Thumbnail rendering for staff payment rows (Sonar S3776 extraction).
Widget staffPaymentThumbImage({
  required String resolved,
  required Widget Function() placeholder,
}) {
  if (resolved.isEmpty) return placeholder();

  if (resolved.startsWith(AppStrings.dataImagePrefix)) {
    return _staffPaymentDataUrlThumb(resolved, placeholder);
  }

  final looksLikeBase64 = !resolved.startsWith('http') &&
      !resolved.startsWith('/') &&
      resolved.length > 100 &&
      resolved.length < 200000;
  if (looksLikeBase64) {
    final fromB64 = _staffPaymentBase64Thumb(resolved, placeholder);
    if (fromB64 != null) return fromB64;
  }

  return ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: Image.network(
      resolved,
      width: 54,
      height: 54,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => placeholder(),
    ),
  );
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
