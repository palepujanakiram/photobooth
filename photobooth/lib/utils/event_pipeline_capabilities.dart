import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// What this runtime can do for the event processor.
///
/// The **queue** is shared (ZenAI ledger + local replica). Card ingest, PTP
/// capture and USB print stay on the box that has the hardware. Phone and web
/// can still **capture** with the built-in camera or a webcam; they just cannot
/// drive USB.
class EventPipelineCapabilities {
  const EventPipelineCapabilities({
    required this.hasLocalLedger,
    required this.canImportCard,
    required this.canCapturePtp,
    required this.canPrintUsb,
    this.canCaptureDevice = false,
  });

  /// Queue and settings only — no USB, no SQLite replica, no device camera.
  const EventPipelineCapabilities.operatorOnly()
      : hasLocalLedger = false,
        canImportCard = false,
        canCapturePtp = false,
        canPrintUsb = false,
        canCaptureDevice = false;

  /// Android event box: local replica plus hardware workers, and the device
  /// camera when no Canon is on USB.
  const EventPipelineCapabilities.booth()
      : hasLocalLedger = true,
        canImportCard = true,
        canCapturePtp = true,
        canPrintUsb = true,
        canCaptureDevice = true;

  final bool hasLocalLedger;
  final bool canImportCard;
  final bool canCapturePtp;
  final bool canPrintUsb;

  /// Built-in camera or webcam (phone, tablet, laptop). Independent of PTP.
  final bool canCaptureDevice;

  bool get canImport => canImportCard;
  bool get canCapture => canCapturePtp || canCaptureDevice;

  static EventPipelineCapabilities ofPlatform({
    bool? isWeb,
    TargetPlatform? platform,
  }) {
    final web = isWeb ?? kIsWeb;
    if (web) {
      return const EventPipelineCapabilities(
        hasLocalLedger: false,
        canImportCard: false,
        canCapturePtp: false,
        canPrintUsb: false,
        canCaptureDevice: true,
      );
    }
    final host = platform ?? defaultTargetPlatform;
    if (host == TargetPlatform.android) {
      return const EventPipelineCapabilities.booth();
    }
    // iOS: local replica + the phone camera. No USB PTP or card reader.
    return const EventPipelineCapabilities(
      hasLocalLedger: true,
      canImportCard: false,
      canCapturePtp: false,
      canPrintUsb: false,
      canCaptureDevice: true,
    );
  }
}
