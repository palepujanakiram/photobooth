import '../../models/strip_models.dart';
import '../../utils/app_strings.dart';
import '../../utils/print_size_helpers.dart';
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

  /// Primary compose `imageUrl` (Classic 1-shot 6×4), distinct from [stripCompositeUrl].
  static String? composePrimaryImageUrlFromSession(
    Map<String, dynamic> raw, {
    required String sessionId,
  }) {
    final direct = StaffPaymentsPayloadUtils.pickString(raw, const [
      'imageUrl',
      'image_url',
    ]).trim();
    if (direct.isNotEmpty) {
      return StaffPaymentsPayloadUtils.normalizeImageUrl(
        direct,
        sessionId: sessionId,
      );
    }

    final generated =
        raw['generatedImages'] ?? raw['generated_images'] ?? raw['images'];
    if (generated is! List) return null;
    for (final entry in generated) {
      if (entry is! Map) continue;
      final m = Map<String, dynamic>.from(entry);
      final size = StaffPaymentsPayloadUtils.pickString(m, const [
        'printSize',
        'print_size',
      ]).trim();
      if (size != 's6x4') continue;
      final url = StaffPaymentsPayloadUtils.imageUrlFromGeneratedEntry(
        entry,
        sessionId: sessionId,
      );
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  /// WCM print token for a picked deliverable URL (generatedImages → session print).
  static String? printSizeForImageUrl(
    Map<String, dynamic> raw, {
    required String imageUrl,
    required String sessionId,
  }) {
    final generatedMatch = _printSizeFromGeneratedImages(
      raw,
      imageUrl: imageUrl,
      sessionId: sessionId,
    );
    if (generatedMatch != null) return generatedMatch;

    final generated =
        raw['generatedImages'] ?? raw['generated_images'] ?? raw['images'];
    if (generated is List) {
      for (final entry in generated) {
        final url = StaffPaymentsPayloadUtils.imageUrlFromGeneratedEntry(
          entry,
          sessionId: sessionId,
        );
        if (url != null &&
            imageUrlsReferToSameDeliverable(url, imageUrl)) {
          return null;
        }
      }
    }

    final printBlock = raw['print'];
    if (printBlock is Map) {
      final fromPrint = StaffPaymentsPayloadUtils.pickString(
        Map<String, dynamic>.from(printBlock),
        const ['size', 'printSize', 'print_size'],
      ).trim();
      if (fromPrint.isNotEmpty) return fromPrint;
    }

    final top = StaffPaymentsPayloadUtils.pickString(raw, const [
      'printSize',
      'print_size',
    ]).trim();
    return top.isEmpty ? null : top;
  }

  /// Classic compose shot count when present on session payload (1 → 6×4, 4 → strip).
  static int? classicComposeShotCountFromSession(Map<String, dynamic> raw) {
    final captured = raw['capturedImages'] ?? raw['captured_images'];
    if (captured is List) {
      if (captured.length == 1) return 1;
      if (captured.length == kStripShotCount) return kStripShotCount;
    }
    final shotCount = raw['shotCount'] ?? raw['shot_count'];
    if (shotCount is int && (shotCount == 1 || shotCount == kStripShotCount)) {
      return shotCount;
    }
    return null;
  }

  static String? _printSizeFromGeneratedImages(
    Map<String, dynamic> raw, {
    required String imageUrl,
    required String sessionId,
  }) {
    final generated =
        raw['generatedImages'] ?? raw['generated_images'] ?? raw['images'];
    if (generated is! List) return null;
    for (final entry in generated) {
      if (entry is! Map) continue;
      final url = StaffPaymentsPayloadUtils.imageUrlFromGeneratedEntry(
        entry,
        sessionId: sessionId,
      );
      if (url == null ||
          !imageUrlsReferToSameDeliverable(url, imageUrl)) {
        continue;
      }
      final size = StaffPaymentsPayloadUtils.pickString(
        Map<String, dynamic>.from(entry),
        const ['printSize', 'print_size'],
      ).trim();
      if (size.isNotEmpty) return size;
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
