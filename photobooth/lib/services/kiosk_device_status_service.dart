import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:uvccamera/uvccamera.dart';

import '../models/app_settings_model.dart';
import '../models/kiosk_device_status.dart';
import '../utils/app_strings.dart';
import '../utils/printer_endpoint.dart';
import '../utils/uvc_webcam_filter.dart';
import 'dnp/dnp_print_transport.dart';
import 'dnp/dnp_usb_client.dart';
import 'dnp/dnp_wifi_client.dart';
import 'receipt/receipt_print_bridge.dart';
import '../utils/receipt_printer_config.dart';

/// Probes booth hardware for the kiosk settings status panel.
class KioskDeviceStatusService {
  KioskDeviceStatusService({
    DnpUsbClient? usbClient,
    DnpWifiClient? wifiClient,
    ReceiptPrintBridge? receiptBridge,
    Future<bool> Function()? probeUvcDevices,
    bool Function()? isAndroid,
    bool Function()? isWeb,
    Duration? wifiDiscoverTimeout,
  })  : _usb = usbClient ?? DnpUsbClient(),
        _wifi = wifiClient ?? DnpWifiClient(),
        _receipt = receiptBridge ?? ReceiptPrintBridge(),
        _probeUvcDevices = probeUvcDevices ?? _defaultUvcProbe,
        _isAndroid = isAndroid ?? (() => !kIsWeb && Platform.isAndroid),
        _isWeb = isWeb ?? (() => kIsWeb),
        _wifiDiscoverTimeout =
            wifiDiscoverTimeout ?? const Duration(seconds: 5);

  final DnpUsbClient _usb;
  final DnpWifiClient _wifi;
  final ReceiptPrintBridge _receipt;
  final Future<bool> Function() _probeUvcDevices;
  final bool Function() _isAndroid;
  final bool Function() _isWeb;
  final Duration _wifiDiscoverTimeout;

  Future<KioskDeviceStatusSnapshot> probe({AppSettingsModel? settings}) async {
    final transport = resolveDnpPrintTransport(settings);
    final results = await Future.wait([
      _probeDnpPrinter(transport, settings),
      _probeReceiptPrinter(settings),
      _probeUsbCamera(),
    ]);
    return KioskDeviceStatusSnapshot(
      dnpPrinter: results[0],
      receiptPrinter: results[1],
      usbCamera: results[2],
    );
  }

  Future<KioskDeviceStatusEntry> _probeDnpPrinter(
    DnpPrintTransport transport,
    AppSettingsModel? settings,
  ) async {
    if (_isWeb()) {
      return _dnpEntry(connected: false, transport: KioskDeviceTransport.wifi);
    }

    switch (transport) {
      case DnpPrintTransport.usb:
        final usbPresent = _isAndroid() && await _usb.probeDevicePresent();
        return _dnpEntry(
          connected: usbPresent,
          transport: KioskDeviceTransport.usb,
        );
      case DnpPrintTransport.wifi:
        final wifiOk = await _probeDnpWifi(settings);
        return _dnpEntry(
          connected: wifiOk,
          transport: KioskDeviceTransport.wifi,
        );
      case DnpPrintTransport.auto:
        if (_isAndroid()) {
          final usbPresent = await _usb.probeDevicePresent();
          if (usbPresent) {
            return _dnpEntry(
              connected: true,
              transport: KioskDeviceTransport.usb,
            );
          }
        }
        final wifiOk = await _probeDnpWifi(settings);
        return _dnpEntry(
          connected: wifiOk,
          transport: KioskDeviceTransport.wifi,
        );
    }
  }

  Future<bool> _probeDnpWifi(AppSettingsModel? settings) async {
    if (kIsWeb) return false;
    try {
      final cached = _wifi.printerBaseUrl;
      if (cached != null && cached.trim().isNotEmpty) return true;

      final url = await _wifi
          .discover(parallelism: 32)
          .timeout(_wifiDiscoverTimeout);
      if (url != null && url.trim().isNotEmpty) return true;

      final configured = resolvePrinterEndpoint(settings);
      if (configured.host.isNotEmpty) {
        return _wifi.probeBaseUrl(configured.baseUrl).timeout(
              _wifiDiscoverTimeout,
            );
      }
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  KioskDeviceStatusEntry _dnpEntry({
    required bool connected,
    required KioskDeviceTransport transport,
  }) {
    return KioskDeviceStatusEntry(
      deviceName: AppStrings.kioskDeviceDnpPrinter,
      connected: connected,
      transport: transport,
    );
  }

  Future<KioskDeviceStatusEntry> _probeReceiptPrinter(
    AppSettingsModel? settings,
  ) async {
    if (!isReceiptPrinterEnabled(settings)) {
      return const KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceReceiptPrinter,
        connected: false,
        configured: false,
        transport: KioskDeviceTransport.wifi,
      );
    }
    if (kIsWeb) {
      return const KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceReceiptPrinter,
        connected: false,
        configured: true,
        transport: KioskDeviceTransport.wifi,
      );
    }

    try {
      final probe = await _receipt
          .probe(settings: settings)
          .timeout(_wifiDiscoverTimeout);
      return KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceReceiptPrinter,
        connected: probe.connected,
        configured: probe.configured,
        transport: probe.transport == ReceiptPrinterTransport.usb
            ? KioskDeviceTransport.usb
            : KioskDeviceTransport.wifi,
      );
    } on TimeoutException {
      return const KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceReceiptPrinter,
        connected: false,
        configured: true,
        transport: KioskDeviceTransport.wifi,
      );
    } catch (_) {
      return const KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceReceiptPrinter,
        connected: false,
        configured: true,
        transport: KioskDeviceTransport.wifi,
      );
    }
  }

  Future<KioskDeviceStatusEntry> _probeUsbCamera() async {
    if (kIsWeb || !_isAndroid()) {
      return const KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceUsbCamera,
        connected: false,
        transport: KioskDeviceTransport.usb,
      );
    }
    final present = await _probeUvcDevices();
    return KioskDeviceStatusEntry(
      deviceName: AppStrings.kioskDeviceUsbCamera,
      connected: present,
      transport: KioskDeviceTransport.usb,
    );
  }

  static Future<bool> _defaultUvcProbe() async {
    try {
      if (!await UvcCamera.isSupported()) return false;
      final devices = await UvcCamera.getDevices();
      return hasUvcWebcamDevices(devices);
    } catch (_) {
      return false;
    }
  }
}
