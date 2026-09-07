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

  Future<PrinterConsumables> read() async {
    try {
      final raw = await _channel
          .invokeMapMethod<Object?, Object?>('getPrinterStatus');
      return PrinterConsumables.fromStatusMap(raw);
    } on PlatformException catch (e) {
      if (e.code == 'NO_PRINTER') return PrinterConsumables.offline;
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
