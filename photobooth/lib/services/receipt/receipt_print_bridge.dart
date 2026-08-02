import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/app_settings_model.dart';
import '../../utils/app_strings.dart';
import '../../utils/exceptions.dart';
import '../../utils/logger.dart';
import '../../utils/receipt_printer_endpoint.dart';
import '../dnp/dnp_wifi_client.dart';
import '../receipt_printer_service_io.dart';
import 'receipt_escpos_normalizer.dart';
import 'receipt_printer_profile.dart';
import 'receipt_usb_client.dart';
import 'receipt_wifi_client.dart';

/// Routes ESC/POS receipt jobs: **USB when connected**, else **Wi-Fi subnet
/// discovery** on port 9100, else admin `/api/settings` host (or API-provided IP).
class ReceiptPrintBridge {
  ReceiptPrintBridge({
    ReceiptUsbClient? usbClient,
    ReceiptWifiClient? wifiClient,
    ReceiptPrinterService? lanService,
    bool Function()? isAndroid,
    Future<bool> Function()? prepareWifiNetwork,
  })  : _usb = usbClient ?? ReceiptUsbClient(),
        _wifi = wifiClient ?? ReceiptWifiClient(),
        _lan = lanService ?? ReceiptPrinterService(),
        _isAndroid = isAndroid ?? _defaultIsAndroid,
        _prepareWifiNetwork = prepareWifiNetwork ?? prepareDnpWifiNetwork;

  final ReceiptUsbClient _usb;
  final ReceiptWifiClient _wifi;
  final ReceiptPrinterService _lan;
  final bool Function() _isAndroid;
  final Future<bool> Function() _prepareWifiNetwork;

  bool _usbReady = false;

  static bool _defaultIsAndroid() => !kIsWeb && Platform.isAndroid;

  void resetSession() {
    _usbReady = false;
    _wifi.clear();
  }

  /// Delivers [bytes] using USB, Wi-Fi discovery, API host, or settings fallback.
  Future<void> deliverEscPos({
    required Uint8List bytes,
    AppSettingsModel? settings,
    String? apiHost,
    int? apiPort,
  }) async {
    final payload = ReceiptEscPosNormalizer.normalize(bytes);
    if (payload.isEmpty) {
      throw ApiException(AppStrings.receiptPrintEmptyPayload);
    }

    if (_isAndroid()) {
      final usbPresent = await _usbDevicePresent();
      if (usbPresent) {
        try {
          await _printUsb(payload);
          return;
        } on PlatformException catch (e) {
          if (!_shouldFallbackFromUsb(e)) {
            throw ApiException(
              '${AppStrings.receiptPrintFailedGeneric} (${e.message ?? e.code})',
            );
          }
          AppLogger.warning(
            'Receipt USB print unavailable (${e.code}); trying Wi-Fi discovery',
          );
          _usbReady = false;
        }
      } else {
        AppLogger.debug(
          'Receipt USB not detected; discovering printer on Wi-Fi',
        );
      }
    }

    final endpoint = await _resolveWifiEndpoint(
      settings: settings,
      apiHost: apiHost,
      apiPort: apiPort,
    );
    await _lan.sendEscPosBytes(
      host: endpoint.host,
      port: endpoint.port,
      bytes: payload,
    );
  }

  /// True when a USB receipt printer is visible (Android only).
  Future<bool> probeUsbPresent() => _usbDevicePresent();

  /// Probes receipt printer: USB first, then Wi-Fi discovery, then settings.
  Future<ReceiptPrinterProbeResult> probe({
    AppSettingsModel? settings,
  }) async {
    if (_isAndroid()) {
      final usbPresent = await _usbDevicePresent();
      if (usbPresent) {
        return const ReceiptPrinterProbeResult(
          connected: true,
          transport: ReceiptPrinterTransport.usb,
          configured: true,
        );
      }
    }

    final wifiHost = await _discoverWifiHost();
    if (wifiHost != null) {
      return ReceiptPrinterProbeResult(
        connected: true,
        transport: ReceiptPrinterTransport.wifi,
        configured: true,
        host: wifiHost,
        port: _wifi.port,
      );
    }

    final configured = resolveReceiptPrinterEndpoint(settings);
    if (configured.isConfigured) {
      final reachable = await _wifi.probeHost(
        configured.host,
        port: configured.port,
      );
      return ReceiptPrinterProbeResult(
        connected: reachable,
        transport: ReceiptPrinterTransport.wifi,
        configured: true,
        host: configured.host,
        port: configured.port,
      );
    }

    return const ReceiptPrinterProbeResult(
      connected: false,
      transport: ReceiptPrinterTransport.wifi,
      configured: false,
    );
  }

  Future<bool> _usbDevicePresent() async {
    if (!_isAndroid()) return false;
    try {
      return await _usb.probeDevicePresent();
    } catch (_) {
      return false;
    }
  }

  bool _shouldFallbackFromUsb(PlatformException e) {
    const recoverable = {
      'NO_PRINTER',
      'CONNECT_FAILED',
      'PERMISSION_DENIED',
      'PRINT_ERROR',
    };
    return recoverable.contains(e.code);
  }

  Future<void> _printUsb(Uint8List bytes) async {
    if (!_usbReady) {
      await _usb.ensureConnected();
      _usbReady = true;
    }
    await _usb.sendEscPos(bytes);
  }

  Future<ReceiptPrinterEndpoint> _resolveWifiEndpoint({
    AppSettingsModel? settings,
    String? apiHost,
    int? apiPort,
  }) async {
    final discovered = await _discoverWifiHost();
    if (discovered != null) {
      AppLogger.debug('Receipt printer discovered on Wi-Fi at $discovered:${_wifi.port}');
      return ReceiptPrinterEndpoint(host: discovered, port: _wifi.port);
    }

    final api = apiHost?.trim() ?? '';
    if (api.isNotEmpty) {
      final port = apiPort ?? ReceiptPrinterEndpoint.defaultPort;
      AppLogger.debug('Receipt Wi-Fi discovery found no printer; using API host $api:$port');
      return ReceiptPrinterEndpoint(host: api, port: port);
    }

    final configured = resolveReceiptPrinterEndpoint(settings);
    if (configured.isConfigured) {
      AppLogger.debug(
        'Receipt Wi-Fi discovery found no printer; using configured '
        '${configured.host}:${configured.port}',
      );
      return configured;
    }

    throw ApiException(
      'No receipt printer found. Connect the Posiflow printer via USB or '
      'ensure it is on the same Wi-Fi network as this kiosk.',
    );
  }

  Future<String?> _discoverWifiHost() async {
    if (_wifi.host != null && _wifi.host!.trim().isNotEmpty) {
      return _wifi.host;
    }

    if (_isAndroid()) {
      final bound = await _prepareWifiNetwork();
      if (!bound) {
        AppLogger.debug(
          'Wi-Fi network bind failed; skipping receipt subnet discovery',
        );
        return null;
      }
    }

    return _wifi.discover();
  }
}

enum ReceiptPrinterTransport { usb, wifi }

class ReceiptPrinterProbeResult {
  const ReceiptPrinterProbeResult({
    required this.connected,
    required this.transport,
    required this.configured,
    this.host,
    this.port = ReceiptPrinterEndpoint.defaultPort,
  });

  final bool connected;
  final ReceiptPrinterTransport transport;
  final bool configured;
  final String? host;
  final int port;
}
