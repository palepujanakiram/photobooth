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

  /// Clears Wi‑Fi discovery cache and drops the native USB claim so the next
  /// print re-opens a fresh pipe (Staff reprint after guest checkout).
  Future<void> resetSession() async {
    _usbReady = false;
    _wifi.clear();
    await _usb.disconnect();
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

    if (transport == DnpPrintTransport.usb) {
      if (!_isAndroid()) {
        throw PrintException('DNP USB print is only supported on Android');
      }
      await _printUsb(localPath, size, networkPrintSize, copies);
      return;
    }

    if (transport == DnpPrintTransport.wifi) {
      await _printWifi(
        localPath,
        size.wifiPrintSize,
        copies,
        settings: settings,
      );
      return;
    }

    await _printAuto(
      localPath: localPath,
      size: size,
      networkPrintSize: networkPrintSize,
      copies: copies,
      settings: settings,
    );
  }

  /// Auto hunt: kiosk printer IP (if set) → USB → Wi‑Fi discovery.
  Future<void> _printAuto({
    required String localPath,
    required DnpPrintSize size,
    required String networkPrintSize,
    required int copies,
    required AppSettingsModel? settings,
  }) async {
    if (hasConfiguredPrinterHost(settings)) {
      if (await _tryWifiPrint(
        localPath,
        size.wifiPrintSize,
        copies,
        settings: settings,
        allowConfiguredHost: true,
      )) {
        return;
      }
      AppLogger.warning(
        'DNP kiosk printer IP failed; trying USB / Wi-Fi discovery',
      );
      _wifi.clear();
    }

    if (_isAndroid()) {
      final usbPresent = await _usbDevicePresent();
      if (usbPresent &&
          await _tryUsbPrintWithFallback(
            localPath,
            size,
            networkPrintSize,
            copies,
          )) {
        return;
      }
      if (!usbPresent) {
        AppLogger.debug('DNP USB not detected; trying Wi-Fi discovery');
      }
    }

    await _printWifi(
      localPath,
      size.wifiPrintSize,
      copies,
      settings: settings,
      allowConfiguredHost: false,
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

  bool _isRecoverableUsbError(PlatformException e) {
    const recoverable = {
      'NO_PRINTER',
      'CONNECT_FAILED',
      'PERMISSION_DENIED',
      'STATUS_ERROR',
    };
    return recoverable.contains(e.code);
  }

  /// Returns true when USB print finished; false when recoverable and caller
  /// should continue the hunt.
  Future<bool> _tryUsbPrintWithFallback(
    String localPath,
    DnpPrintSize size,
    String networkPrintSize,
    int copies,
  ) async {
    try {
      await _printUsb(localPath, size, networkPrintSize, copies);
      return true;
    } on PlatformException catch (e) {
      if (!_isRecoverableUsbError(e)) rethrow;
      AppLogger.warning(
        'DNP USB print unavailable (${e.code}); continuing hunt',
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
    try {
      await _usb.print(
        filePath: filePath,
        paperSize: size.usbLabel,
        printSize: networkPrintSize,
        copies: copies,
      );
    } on PlatformException catch (e) {
      if (!_isStaleUsbWriteError(e)) rethrow;
      AppLogger.warning(
        'DNP USB write failed on stale claim; reclaiming and retrying once',
      );
      await _usb.disconnect();
      _usbReady = false;
      await _usb.ensureConnected();
      _usbReady = true;
      await _usb.print(
        filePath: filePath,
        paperSize: size.usbLabel,
        printSize: networkPrintSize,
        copies: copies,
      );
    }
  }

  bool _isStaleUsbWriteError(PlatformException e) {
    if (e.code != 'PRINT_ERROR') return false;
    final msg = (e.message ?? '').toLowerCase();
    return msg.contains('usb write failed');
  }

  /// Returns true when Wi‑Fi print finished; false on failure so hunt can continue.
  Future<bool> _tryWifiPrint(
    String filePath,
    String printSize,
    int copies, {
    AppSettingsModel? settings,
    bool allowConfiguredHost = true,
  }) async {
    try {
      await _printWifi(
        filePath,
        printSize,
        copies,
        settings: settings,
        allowConfiguredHost: allowConfiguredHost,
      );
      return true;
    } catch (e) {
      AppLogger.warning('DNP Wi-Fi print attempt failed: $e');
      _wifi.clear();
      return false;
    }
  }

  Future<void> _printWifi(
    String filePath,
    String printSize,
    int copies, {
    AppSettingsModel? settings,
    bool allowConfiguredHost = true,
  }) async {
    await _ensureWifiPrinterReady(
      settings,
      allowConfiguredHost: allowConfiguredHost,
    );
    await _wifi.print(
      jpegFile: File(filePath),
      printSize: printSize,
      copies: copies,
    );
  }

  /// Prefer kiosk [AppSettingsModel.printerHost] when allowed; else discover.
  Future<void> _ensureWifiPrinterReady(
    AppSettingsModel? settings, {
    bool allowConfiguredHost = true,
  }) async {
    if (_wifi.printerBaseUrl != null) return;

    if (allowConfiguredHost) {
      final configured = resolvePrinterEndpoint(settings);
      if (configured.host.isNotEmpty) {
        _wifi.configureBaseUrl(configured.baseUrl);
        AppLogger.debug(
          '🖨️ Using kiosk printer IP ${configured.baseUrl}${configured.path}',
        );
        return;
      }
    }

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

    if (_isAndroid()) {
      throw PrintException(
        'No DNP printer found on Wi-Fi. Connect this device to the same '
        'network as the DNP WCM Plus module, or set printer IP in kiosk settings.',
      );
    }
    throw PrintException(
      'No DNP printer found on Wi-Fi. Check that the WCM Plus module is on '
      'and this device is on the same network, or set printer IP in kiosk settings.',
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
