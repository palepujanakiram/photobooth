import 'package:flutter/services.dart';

import '../../models/event_pipeline/printer_consumables.dart';
import '../../utils/logger.dart';

/// Reads live DNP status for the print queue.
///
/// Uses the **existing** `getPrinterStatus` method on the DNP channel, which
/// already returns the status code, its decoded label and a ready flag. No new
/// native code was needed — the codes were being decoded in Kotlin and thrown
/// away as an exception string, and this is what puts them to work.
class PrinterStatusReader {
  PrinterStatusReader({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  /// Matches `DnpUsbMethodChannel.METHOD_CHANNEL`.
  static const String channelName = 'com.srisarani.fotozenai/dnp_usb';

  final MethodChannel _channel;

  /// Whether a DNP printer is on the USB bus at all.
  ///
  /// Needs no open connection and no permission — it is a device-list lookup,
  /// which is why it can answer when a status read cannot.
  Future<bool> _probePresence() async {
    try {
      return await _channel.invokeMethod<bool>('probeDevice') ?? false;
    } catch (e) {
      AppLogger.debug('Printer probe failed: $e');
      return false;
    }
  }

  /// Opens the printer, showing Android's USB permission dialog if needed.
  ///
  /// The operator's way out of [PrinterReadiness.needsPermission], and the only
  /// thing that makes a status read work afterwards.
  Future<bool> requestPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException catch (e) {
      AppLogger.warning('Printer permission request failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<PrinterConsumables> read() async {
    try {
      final raw = await _channel
          .invokeMapMethod<Object?, Object?>('getPrinterStatus');
      return PrinterConsumables.fromStatusMap(raw);
    } on PlatformException catch (e) {
      // `getPrinterStatus` needs an **open** connection, and the native side
      // only opens one when permission is requested. So NO_PRINTER covers two
      // very different situations, and they need opposite responses from an
      // operator: no cable, or an unanswered Allow dialog. Ask the bus which
      // it is rather than reporting both as absent.
      if (e.code == 'NO_PRINTER') {
        return await _probePresence()
            ? PrinterConsumables.needsPermission
            : PrinterConsumables.offline;
      }
      // A status query that errors is not proof the printer is broken — some TV
      // USB hosts fail it routinely — so treat it the way the native side
      // treats an unreadable status and let the print attempt decide.
      AppLogger.debug('Printer status unreadable: ${e.message}');
      return PrinterConsumables.unknown;
    } on MissingPluginException {
      return PrinterConsumables.unknown;
    }
  }
}
