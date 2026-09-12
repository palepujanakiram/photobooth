import 'dart:async';

import 'package:flutter/services.dart';

/// What the platform reported about a card or reader.
enum CardEventKind {
  /// A volume finished mounting. **Not** a signal that it is scannable yet —
  /// MediaStore indexes afterwards, so the caller must wait for the count to
  /// settle before reporting how many photos a card holds.
  mounted,

  unmounted,

  /// The reader appeared on USB. Fires before [mounted], and sometimes without
  /// it when `vold` declines to mount the volume.
  usbAttached,

  usbDetached,
}

class CardEvent {
  const CardEvent({
    required this.kind,
    this.path,
    this.vendorId,
    this.productId,
    this.productName,
    this.isMassStorage = false,
  });

  final CardEventKind kind;
  final String? path;
  final int? vendorId;
  final int? productId;
  final String? productName;

  /// USB interface class 8 — i.e. this really is a card reader or drive.
  final bool isMassStorage;

  bool get isInsert =>
      kind == CardEventKind.mounted || kind == CardEventKind.usbAttached;

  bool get isRemoval =>
      kind == CardEventKind.unmounted || kind == CardEventKind.usbDetached;

  static CardEvent? fromMap(Map<Object?, Object?> map) {
    final kind = switch ((map['kind'] ?? '').toString()) {
      'mounted' => CardEventKind.mounted,
      'unmounted' => CardEventKind.unmounted,
      'usbAttached' => CardEventKind.usbAttached,
      'usbDetached' => CardEventKind.usbDetached,
      _ => null,
    };
    if (kind == null) return null;
    return CardEvent(
      kind: kind,
      path: map['path'] as String?,
      vendorId: map['vendorId'] as int?,
      productId: map['productId'] as int?,
      productName: map['productName'] as String?,
      isMassStorage: map['isMassStorage'] == true,
    );
  }
}

/// Card insert and removal, as a stream.
///
/// Backed by a **runtime** broadcast receiver, which is why this works without
/// `device_filter.xml`: that file only drives the manifest filter that launches a
/// closed app, while a registered receiver sees every device while the app runs.
/// Confirmed in the field — the existing `uvccamera` monitor already logs the
/// reader's attach and detach today before discarding it as non-UVC.
class CardDetectChannel {
  CardDetectChannel({EventChannel? channel})
      : _channel = channel ?? const EventChannel(channelName);

  static const String channelName =
      'com.srisarani.fotozenai/event_card_detect';

  final EventChannel _channel;

  Stream<CardEvent> events() {
    return _channel.receiveBroadcastStream().transform(
          StreamTransformer<dynamic, CardEvent>.fromHandlers(
            handleData: (data, sink) {
              if (data is! Map<Object?, Object?>) return;
              final event = CardEvent.fromMap(data);
              if (event != null) sink.add(event);
            },
            // A platform error must not tear the stream down — the operator can
            // still scan manually, and the button is the documented fallback.
            handleError: (error, stackTrace, sink) {},
          ),
        );
  }
}
