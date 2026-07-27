import '../../utils/app_strings.dart';
import '../../utils/secure_image_url.dart';
import 'staff_payments_payload_utils.dart';

/// Collects all printable session image URLs for staff multi-print.
abstract final class StaffPaymentsSessionImages {
  /// From enriched payment payload (`sessionImages`) or nested session fields.
  static List<String> fromPaymentPayload(
    Map<String, dynamic> payment, {
    required String sessionId,
  }) {
    final fromList = _urlsFromDynamicList(
      payment['sessionImages'] ?? payment['session_images'],
      sessionId: sessionId,
    );
    if (fromList.isNotEmpty) return fromList;

    final embedded = payment['session'];
    if (embedded is Map) {
      return fromSessionMap(
        Map<String, dynamic>.from(embedded),
        sessionId: sessionId,
      );
    }
    return const [];
  }

  static List<String> fromSessionMap(
    Map<String, dynamic> raw, {
    required String sessionId,
  }) {
    final out = <String>[];
    void push(String? rawUrl) {
      final t = rawUrl?.trim() ?? '';
      if (t.isEmpty) return;
      final normalized = StaffPaymentsPayloadUtils.normalizeImageUrl(
        t,
        sessionId: sessionId,
      );
      if (normalized.isEmpty) return;
      if (!out.contains(normalized)) out.add(normalized);
    }

    push(StaffPaymentsPayloadUtils.pickString(raw, const [
      'stripCompositeUrl',
      'strip_composite_url',
    ]));
    push(StaffPaymentsPayloadUtils.pickString(raw, const [
      'surpriseImageUrl',
      'surprise_image_url',
    ]));

    final generated =
        raw['generatedImages'] ?? raw['generated_images'] ?? raw['images'];
    if (generated is List) {
      for (final entry in generated) {
        final fromEntry = StaffPaymentsPayloadUtils.imageUrlFromGeneratedEntry(
          entry,
          sessionId: sessionId,
        );
        if (fromEntry != null) push(fromEntry);
      }
    }

    push(StaffPaymentsPayloadUtils.pickString(raw, const [
      'latestImageUrl',
      'latest_image_url',
    ]));

    return out;
  }

  static List<String> _urlsFromDynamicList(
    dynamic list, {
    required String sessionId,
  }) {
    if (list is! List || list.isEmpty) return const [];
    final out = <String>[];
    for (final entry in list) {
      if (entry is! String) continue;
      final normalized = StaffPaymentsPayloadUtils.normalizeImageUrl(
        entry,
        sessionId: sessionId,
      );
      if (normalized.isEmpty) continue;
      if (!out.contains(normalized)) out.add(normalized);
    }
    return out;
  }

  /// Strip composite URL from payment / session payload (for print-size inference).
  static String? stripCompositeUrlFromPayment(
    Map<String, dynamic> payment, {
    required String sessionId,
  }) {
    final direct = StaffPaymentsPayloadUtils.pickString(payment, const [
      'stripCompositeUrl',
      'strip_composite_url',
    ]).trim();
    if (direct.isNotEmpty) {
      return StaffPaymentsPayloadUtils.normalizeImageUrl(
        direct,
        sessionId: sessionId,
      );
    }
    final embedded = payment['session'];
    if (embedded is Map) {
      final fromSession = StaffPaymentsPayloadUtils.pickString(
        Map<String, dynamic>.from(embedded),
        const ['stripCompositeUrl', 'strip_composite_url'],
      ).trim();
      if (fromSession.isNotEmpty) {
        return StaffPaymentsPayloadUtils.normalizeImageUrl(
          fromSession,
          sessionId: sessionId,
        );
      }
    }
    return null;
  }

  /// Short label for staff picker tiles.
  static String labelForIndex(int index, int total) {
    if (total <= 1) return AppStrings.staffPrintPhotoLabel;
    return AppStrings.staffPrintPhotoN(index + 1);
  }

  static String previewUrl(String url) => SecureImageUrl.absolutize(url);
}
