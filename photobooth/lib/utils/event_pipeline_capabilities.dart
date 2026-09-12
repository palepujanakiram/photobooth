import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// What this runtime can do for the event processor.
///
/// The **queue** is shared (ZenAI ledger + local replica). Card ingest, PTP
/// capture and USB print stay on the box that has the hardware. Web and iOS
/// are operator consoles on the same data.
class EventPipelineCapabilities {
  const EventPipelineCapabilities({
    required this.hasLocalLedger,
    required this.canImportCard,
    required this.canCapturePtp,
    required this.canPrintUsb,
  });

  /// Operator-only client: queue and settings, no USB or SQLite replica.
  const EventPipelineCapabilities.operatorOnly()
      : hasLocalLedger = false,
        canImportCard = false,
        canCapturePtp = false,
        canPrintUsb = false;

  /// Android event box: local replica plus hardware workers.
  const EventPipelineCapabilities.booth()
      : hasLocalLedger = true,
        canImportCard = true,
        canCapturePtp = true,
        canPrintUsb = true;

  final bool hasLocalLedger;
  final bool canImportCard;
  final bool canCapturePtp;
  final bool canPrintUsb;

  bool get canImport => canImportCard;
  bool get canCapture => canCapturePtp;

  static EventPipelineCapabilities ofPlatform({
    bool? isWeb,
    TargetPlatform? platform,
  }) {
    final web = isWeb ?? kIsWeb;
    if (web) return const EventPipelineCapabilities.operatorOnly();
    final host = platform ?? defaultTargetPlatform;
    if (host == TargetPlatform.android) {
      return const EventPipelineCapabilities.booth();
    }
    // iOS can hold a replica later; hardware plugins are Android-only today.
    return const EventPipelineCapabilities(
      hasLocalLedger: true,
      canImportCard: false,
      canCapturePtp: false,
      canPrintUsb: false,
    );
  }
}
