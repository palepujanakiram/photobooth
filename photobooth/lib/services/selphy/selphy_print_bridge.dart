import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../utils/constants.dart';
import '../../utils/exceptions.dart';
import '../../utils/logger.dart';
import 'selphy_client.dart';
import 'selphy_print_size.dart';

/// Routes Canon Selphy print jobs to USB or Wi‑Fi (Android only).
///
/// Independent of [DnpPrintBridge] — booths may run both printers together.
class SelphyPrintBridge {
  SelphyPrintBridge({
    SelphyClient? client,
    bool Function()? isAndroid,
    bool? webUnsupported,
  })  : _client = client ?? SelphyClient(),
        _isAndroid = isAndroid ?? _defaultIsAndroid,
        _webUnsupported = webUnsupported ?? kIsWeb;

  final SelphyClient _client;
  final bool Function() _isAndroid;
  final bool _webUnsupported;

  static bool _defaultIsAndroid() => !kIsWeb && Platform.isAndroid;

  bool _usbReady = false;
  bool _wifiReady = false;

  Future<void> resetSession() async {
    _usbReady = false;
    _wifiReady = false;
    await _client.resetSession();
  }

  /// Quick presence check for kiosk status / dual-print gating.
  Future<({bool connected, String? transport})> probe() async {
    if (_webUnsupported || !_isAndroid()) {
      return (connected: false, transport: null);
    }
    try {
      if (await _client.probeUsbPresent()) {
        return (connected: true, transport: 'usb');
      }
    } catch (_) {
      // Fall through to Wi‑Fi.
    }

    try {
      await _client.discoverWifi();
      return (connected: true, transport: 'wifi');
    } on PlatformException catch (e) {
      AppLogger.debug('Selphy Wi-Fi probe: ${e.code}');
      return (connected: false, transport: 'wifi');
    } catch (_) {
      return (connected: false, transport: 'wifi');
    } finally {
      // Status probe must not leave the process bound to the printer AP.
      await _client.releaseWifi();
    }
  }

  Future<void> printImage({
    required XFile imageFile,
    required String networkPrintSize,
    int quantity = AppConstants.kDefaultPrintCopies,
  }) async {
    if (_webUnsupported) {
      throw PrintException('Canon Selphy print is not supported on web');
    }
    if (!_isAndroid()) {
      throw PrintException('Canon Selphy print is only supported on Android');
    }

    final copies = quantity.clamp(
      AppConstants.kDefaultPrintCopies,
      AppConstants.kMaxPrintCopies,
    );
    final paper = SelphyPrintSize.fromNetworkPrintSize(networkPrintSize);
    final localPath = await _resolveLocalPath(imageFile);

    if (await _tryUsbPrint(localPath, paper.paperSize, copies)) {
      return;
    }

    await _printWifi(localPath, paper.paperSize, copies);
  }

  Future<bool> _tryUsbPrint(
    String filePath,
    String paperSize,
    int copies,
  ) async {
    try {
      final present = await _client.probeUsbPresent();
      if (!present) return false;
      await _printUsb(filePath, paperSize, copies);
      return true;
    } on PlatformException catch (e) {
      if (!_isRecoverableUsbError(e)) rethrow;
      AppLogger.warning(
        'Selphy USB print unavailable (${e.code}); trying Wi-Fi',
      );
      _usbReady = false;
      return false;
    }
  }

  bool _isRecoverableUsbError(PlatformException e) {
    const recoverable = {
      'NO_PRINTER',
      'NO_PERMISSION',
      'PERMISSION_DENIED',
      'PERMISSION_REQUEST_FAILED',
      'PREPARE_FAILED',
    };
    return recoverable.contains(e.code);
  }

  Future<void> _printUsb(
    String filePath,
    String paperSize,
    int copies,
  ) async {
    if (!_usbReady) {
      await _client.ensureUsbConnected();
      _usbReady = true;
    }
    await _client.print(
      filePath: filePath,
      transport: 'usb',
      paperSize: paperSize,
      copies: copies,
    );
  }

  Future<void> _printWifi(
    String filePath,
    String paperSize,
    int copies,
  ) async {
    try {
      if (!_wifiReady) {
        await _client.discoverWifi();
        _wifiReady = true;
      }
      await _client.print(
        filePath: filePath,
        transport: 'wifi',
        paperSize: paperSize,
        copies: copies,
      );
    } finally {
      // Selphy Direct AP has no internet — always unbind after the job.
      await _client.releaseWifi();
      _wifiReady = false;
    }
  }

  Future<String> _resolveLocalPath(XFile imageFile) async {
    final path = imageFile.path.trim();
    if (path.isEmpty) {
      throw PrintException('Image file path is empty');
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      throw PrintException('Image must be saved locally before Selphy print');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw PrintException('Image file not found for Selphy printing');
    }
    return path;
  }
}
