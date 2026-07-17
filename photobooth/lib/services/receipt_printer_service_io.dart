import 'dart:io';
import 'dart:typed_data';

import '../utils/app_strings.dart';
import '../utils/exceptions.dart';
import '../utils/logger.dart';
import 'receipt_printer_payload.dart';

/// Sends ESC/POS bytes to a LAN thermal printer over raw TCP (Posiflow :9100).
class ReceiptPrinterService {
  ReceiptPrinterService({
    this.connectTimeout = const Duration(seconds: 5),
  });

  final Duration connectTimeout;

  /// Decode [payloadBase64] and write to [host]:[port].
  Future<void> sendEscPosBase64({
    required String host,
    required int port,
    required String payloadBase64,
  }) async {
    ReceiptPrinterPayload.validateHostPort(host: host, port: port);
    final bytes = ReceiptPrinterPayload.decodeBase64(payloadBase64);
    await sendEscPosBytes(host: host.trim(), port: port, bytes: bytes);
  }

  Future<void> sendEscPosBytes({
    required String host,
    required int port,
    required Uint8List bytes,
  }) async {
    if (bytes.isEmpty) {
      throw ApiException(AppStrings.receiptPrintEmptyPayload);
    }

    Socket? socket;
    try {
      socket = await Socket.connect(
        host,
        port,
        timeout: connectTimeout,
      );
      socket.add(bytes);
      await socket.flush();
      AppLogger.debug(
        'Receipt ESC/POS sent to $host:$port (${bytes.length} bytes)',
      );
    } on SocketException catch (e) {
      AppLogger.error('Receipt printer socket failed: $e', error: e);
      throw ApiException(
        '${AppStrings.receiptPrintFailedGeneric} (${e.message})',
      );
    } catch (e, st) {
      AppLogger.error(
        'Receipt printer send failed: $e',
        error: e,
        stackTrace: st,
      );
      if (e is ApiException) rethrow;
      throw ApiException(AppStrings.receiptPrintFailedGeneric);
    } finally {
      try {
        await socket?.close();
      } catch (_) {
        // ignore close errors
      }
    }
  }
}
