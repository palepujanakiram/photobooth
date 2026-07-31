import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/app_settings_model.dart';
import '../../utils/constants.dart';
import '../../utils/exceptions.dart';
import '../../utils/logger.dart';
import '../../utils/printer_endpoint.dart';
import 'dnp_print_size.dart';
import 'dnp_print_transport.dart';
import 'dnp_usb_client.dart';
import 'dnp_wifi_client.dart';

/// Routes DNP print jobs to USB (Android) or WCM Plus Wi-Fi (iOS + Android).
class DnpPrintBridge {
  DnpPrintBridge({
    DnpUsbClient? usbClient,
    DnpWifiClient? wifiClient,
    bool Function()? isAndroid,
    Future<bool> Function()? prepareWifiNetwork,
    bool? webUnsupported,
  })  : _usb = usbClient ?? DnpUsbClient(),
        _wifi = wifiClient ?? DnpWifiClient(),
        _isAndroid = isAndroid ?? _defaultIsAndroid,
        _prepareWifiNetwork = prepareWifiNetwork ?? prepareDnpWifiNetwork,
        _webUnsupported = webUnsupported ?? kIsWeb;

  final DnpUsbClient _usb;
  final DnpWifiClient _wifi;
  final bool Function() _isAndroid;
  final Future<bool> Function() _prepareWifiNetwork;
  final bool _webUnsupported;

  static bool _defaultIsAndroid() => !kIsWeb && Platform.isAndroid;

  bool _usbReady = false;

  void resetSession() {
    _usbReady = false;
    _wifi.clear();
  }

  Future<void> printImage({
    required XFile imageFile,
    required AppSettingsModel? settings,
    required String networkPrintSize,
    int quantity = AppConstants.kDefaultPrintCopies,
  }) async {
    if (_webUnsupported) {
      throw PrintException('DNP direct print is not supported on web');
    }

    final transport = resolveDnpPrintTransport(settings);
    final copies = quantity.clamp(
      AppConstants.kDefaultPrintCopies,
      AppConstants.kMaxPrintCopies,
    );
    final size = DnpPrintSize.fromNetworkPrintSize(networkPrintSize);
    final localPath = await _resolveLocalPath(imageFile);

    if (_shouldUseUsb(transport)) {
      try {
        await _printUsb(localPath, size, networkPrintSize, copies);
        return;
      } on PlatformException catch (e) {
        if (!_shouldFallbackToWifi(transport, e)) rethrow;
        AppLogger.warning('DNP USB print unavailable, trying WCM Plus Wi-Fi: ${e.code}');
      }
    }

    await _printWifi(
      localPath,
      size.wifiPrintSize,
      copies,
      settings: settings,
    );
  }

  bool _shouldUseUsb(DnpPrintTransport transport) {
    if (!_isAndroid()) return false;
    return transport == DnpPrintTransport.usb ||
        transport == DnpPrintTransport.auto;
  }

  bool _shouldFallbackToWifi(DnpPrintTransport transport, PlatformException e) {
    if (transport == DnpPrintTransport.usb) return false;
    const recoverable = {'NO_PRINTER', 'CONNECT_FAILED', 'PERMISSION_DENIED'};
    return recoverable.contains(e.code);
  }

  Future<void> _printUsb(
    String filePath,
    DnpPrintSize size,
    String networkPrintSize,
    int copies,
  ) async {
    if (!_usbReady) {
      await _usb.ensureConnected();
      _usbReady = true;
    }
    await _usb.print(
      filePath: filePath,
      paperSize: size.usbLabel,
      printSize: networkPrintSize,
      copies: copies,
    );
  }

  Future<void> _printWifi(
    String filePath,
    String printSize,
    int copies, {
    AppSettingsModel? settings,
  }) async {
    await _ensureWifiPrinterReady(settings);
    await _wifi.print(
      jpegFile: File(filePath),
      printSize: printSize,
      copies: copies,
    );
  }

  /// Prefer admin [AppSettingsModel.printerHost]; else Wi-Fi subnet discovery.
  Future<void> _ensureWifiPrinterReady(AppSettingsModel? settings) async {
    final configured = resolvePrinterEndpoint(settings);
    if (configured.host.isNotEmpty) {
      _wifi.configureBaseUrl(configured.baseUrl);
      AppLogger.debug(
        '🖨️ Using configured printer ${configured.baseUrl}'
        '${configured.path}',
      );
      return;
    }

    if (_wifi.printerBaseUrl != null) return;

    if (_isAndroid()) {
      final bound = await _prepareWifiNetwork();
      if (!bound) {
        throw PrintException(
          'Could not reach Wi-Fi. Connect this device to the WCM Plus network, '
          'or set printerHost in booth settings.',
        );
      }
    }
    final url = await _wifi.discover();
    if (url == null) {
      throw PrintException(
        'No WCM Plus printer found on Wi-Fi. Set printerHost in booth '
        'settings, or check the printer module and network.',
      );
    }
    AppLogger.debug('🖨️ Discovered WCM Plus at $url');
  }

  Future<String> _resolveLocalPath(XFile imageFile) async {
    final path = imageFile.path.trim();
    if (path.isEmpty) {
      throw PrintException('Image file path is empty');
    }
    if (path.startsWith('http://') || path.startsWith('https://')) {
      throw PrintException('Image must be saved locally before USB/WCM print');
    }
    final file = File(path);
    if (!await file.exists()) {
      throw PrintException('Image file not found for printing');
    }
    return path;
  }
}
