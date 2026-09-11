import 'package:flutter/services.dart';

import '../../models/event_pipeline/printer_consumables.dart';
import '../../utils/logger.dart';
import '../dnp/dnp_usb_client.dart';

/// Reads live DNP status for the print queue.
///
/// Uses the **existing** `getPrinterStatus` method on the DNP channel, which
/// already returns the status code, its decoded label and a ready flag. No new
/// native code was needed — the codes were being decoded in Kotlin and thrown
/// away as an exception string, and this is what puts them to work.
class PrinterStatusReader {
  PrinterStatusReader({MethodChannel? channel, DnpUsbClient? usbClient})
      : _usb = usbClient ??
            DnpUsbClient(
              channel: channel ?? const MethodChannel(channelName),
            );

  /// Matches `DnpUsbMethodChannel.METHOD_CHANNEL`.
  static const String channelName = 'com.srisarani.fotozenai/dnp_usb';

  /// The kiosk's own DNP client, which owns the channel outright.
  ///
  /// This class adds only the *interpretation* the print queue needs — turning
  /// a status map into a queue action — rather than a second way to talk to the
  /// printer.
  final DnpUsbClient _usb;

  /// Opens the printer, showing Android's USB permission dialog if needed.
  ///
  /// The operator's way out of [PrinterReadiness.needsPermission], and the only
  /// thing that makes a status read work afterwards. Delegated to
  /// [DnpUsbClient] rather than reimplemented: the kiosk print path already
  /// owns connecting to this printer, and two ways to open one USB device is
  /// exactly the drift that ends with them disagreeing.
  Future<bool> requestPermission() async {
    try {
      await _usb.ensureConnected();
      return true;
    } on PlatformException catch (e) {
      AppLogger.warning('Printer permission request failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<PrinterConsumables> read() async {
    try {
      final raw = await _usb.getPrinterStatus();
      return PrinterConsumables.fromStatusMap(raw);
    } on PlatformException catch (e) {
      // `getPrinterStatus` needs an **open** connection, and the native side
      // only opens one when permission is requested. So NO_PRINTER covers two
      // very different situations, and they need opposite responses from an
      // operator: no cable, or an unanswered Allow dialog. Ask the bus which
      // it is rather than reporting both as absent.
      if (e.code == 'NO_PRINTER') {
        return await _usb.probeDevicePresent()
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
