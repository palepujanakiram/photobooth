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

    if (_shouldTryUsbFirst(transport)) {
      final usbPresent = await _usbDevicePresent();
      if (!usbPresent) {
        AppLogger.debug(
          'DNP USB not detected; discovering printer on Wi-Fi',
        );
      } else if (await _tryUsbPrintWithWifiFallback(
        transport,
        localPath,
        size,
        networkPrintSize,
        copies,
      )) {
        return;
      }
    } else if (_shouldUseUsbOnly(transport)) {
      await _printUsb(localPath, size, networkPrintSize, copies);
      return;
    }

    await _printWifi(
      localPath,
      size.wifiPrintSize,
      copies,
      settings: settings,
    );
  }

  /// True when [DnpPrintTransport.auto] should probe USB before Wi-Fi.
  bool _shouldTryUsbFirst(DnpPrintTransport transport) =>
      _isAndroid() && transport == DnpPrintTransport.auto;

  bool _shouldUseUsbOnly(DnpPrintTransport transport) =>
      _isAndroid() && transport == DnpPrintTransport.usb;

  Future<bool> _usbDevicePresent() async {
    if (!_isAndroid()) return false;
    try {
      return await _usb.probeDevicePresent();
    } catch (_) {
      return false;
    }
  }

  bool _shouldFallbackToWifi(DnpPrintTransport transport, PlatformException e) {
    if (transport == DnpPrintTransport.usb) return false;
    const recoverable = {
      'NO_PRINTER',
      'CONNECT_FAILED',
      'PERMISSION_DENIED',
      'STATUS_ERROR',
    };
    return recoverable.contains(e.code);
  }

  /// USB print for [DnpPrintTransport.auto]; returns true when the job finished.
  Future<bool> _tryUsbPrintWithWifiFallback(
    DnpPrintTransport transport,
    String localPath,
    DnpPrintSize size,
    String networkPrintSize,
    int copies,
  ) async {
    try {
      await _printUsb(localPath, size, networkPrintSize, copies);
      return true;
    } on PlatformException catch (e) {
      if (!_shouldFallbackToWifi(transport, e)) rethrow;
      AppLogger.warning(
        'DNP USB print unavailable (${e.code}); trying Wi-Fi discovery',
      );
      _usbReady = false;
      return false;
    }
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

  /// Subnet discovery first; [AppSettingsModel.printerHost] only when discovery fails.
  Future<void> _ensureWifiPrinterReady(AppSettingsModel? settings) async {
    if (_wifi.printerBaseUrl != null) return;

    String? discoveredUrl;
    if (_isAndroid()) {
      final bound = await _prepareWifiNetwork();
      if (bound) {
        discoveredUrl = await _wifi.discover();
      } else {
        AppLogger.debug(
          'Wi-Fi network bind failed; skipping subnet discovery',
        );
      }
    } else {
      discoveredUrl = await _wifi.discover();
    }

    if (discoveredUrl != null) {
      AppLogger.debug('🖨️ Discovered WCM Plus at $discoveredUrl');
      return;
    }

    final configured = resolvePrinterEndpoint(settings);
    if (configured.host.isNotEmpty) {
      _wifi.configureBaseUrl(configured.baseUrl);
      AppLogger.debug(
        '🖨️ Wi-Fi discovery found no printer; using configured '
        '${configured.baseUrl}${configured.path}',
      );
      return;
    }

    if (_isAndroid()) {
      throw PrintException(
        'No DNP printer found on Wi-Fi. Connect this device to the same '
        'network as the DNP WCM Plus module.',
      );
    }
    throw PrintException(
      'No DNP printer found on Wi-Fi. Check that the WCM Plus module is on '
      'and this device is on the same network.',
    );
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
