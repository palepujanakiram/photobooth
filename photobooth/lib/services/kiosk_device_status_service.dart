import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:uvccamera/uvccamera.dart';

import '../models/app_settings_model.dart';
import '../models/kiosk_device_status.dart';
import '../utils/app_strings.dart';
import '../utils/camera_sidecar_config.dart';
import '../utils/canon_sidecar_status_channel.dart';
import '../utils/printer_endpoint.dart';
import '../utils/receipt_printer_config.dart';
import '../utils/uvc_webcam_filter.dart';
import 'dnp/dnp_print_transport.dart';
import 'dnp/dnp_usb_client.dart';
import 'dnp/dnp_wifi_client.dart';
import 'local_camera_service.dart';
import 'receipt/receipt_print_bridge.dart';
import 'selphy/selphy_print_bridge.dart';

/// Probes booth hardware for the kiosk settings status panel.
class KioskDeviceStatusService {
  KioskDeviceStatusService({
    DnpUsbClient? usbClient,
    DnpWifiClient? wifiClient,
    SelphyPrintBridge? selphyBridge,
    ReceiptPrintBridge? receiptBridge,
    Future<bool> Function()? probeUvcDevices,
    Future<bool> Function(CameraSidecarConfig config)? probeDslrSidecar,
    Future<String> Function()? querySidecarNativeState,
    Future<bool> Function()? queryCanonCameraPresent,
    bool Function()? isAndroid,
    bool Function()? isWeb,
    Duration? wifiDiscoverTimeout,
  })  : _usb = usbClient ?? DnpUsbClient(),
        _wifi = wifiClient ?? DnpWifiClient(),
        _selphy = selphyBridge ?? SelphyPrintBridge(),
        _receipt = receiptBridge ?? ReceiptPrintBridge(),
        _probeUvcDevices = probeUvcDevices ?? _defaultUvcProbe,
        _probeDslrSidecar = probeDslrSidecar ?? _defaultDslrSidecarProbe,
        _querySidecarNativeState =
            querySidecarNativeState ?? CanonSidecarStatusChannel.getState,
        _queryCanonCameraPresent =
            queryCanonCameraPresent ?? CanonSidecarStatusChannel.isCameraPresent,
        _isAndroid = isAndroid ?? (() => !kIsWeb && Platform.isAndroid),
        _isWeb = isWeb ?? (() => kIsWeb),
        _wifiDiscoverTimeout =
            wifiDiscoverTimeout ?? const Duration(seconds: 5);

  final DnpUsbClient _usb;
  final DnpWifiClient _wifi;
  final SelphyPrintBridge _selphy;
  final ReceiptPrintBridge _receipt;
  final Future<bool> Function() _probeUvcDevices;
  final Future<bool> Function(CameraSidecarConfig config) _probeDslrSidecar;
  final Future<String> Function() _querySidecarNativeState;
  final Future<bool> Function() _queryCanonCameraPresent;
  final bool Function() _isAndroid;
  final bool Function() _isWeb;
  final Duration _wifiDiscoverTimeout;

  Future<KioskDeviceStatusSnapshot> probe({AppSettingsModel? settings}) async {
    final transport = resolveDnpPrintTransport(settings);
    // Receipt + DSLR are LAN HTTP/TCP and can run together.
    // DNP USB + Selphy USB + UVC all touch Android USB host — never run them in
    // parallel (Android TV / capture-card boxes can hard-freeze the USB stack).
    final receiptFuture = _probeReceiptPrinter(settings);
    final dslrFuture = _probeDslrCamera(settings);
    final dnp = await _probeDnpPrinter(transport, settings);
    final selphy = await _probeSelphyPrinter();
    final usbCamera = await _probeUsbCamera();
    final networked = await Future.wait([receiptFuture, dslrFuture]);
    return KioskDeviceStatusSnapshot(
      dnpPrinter: dnp,
      selphyPrinter: selphy,
      receiptPrinter: networked[0],
      usbCamera: usbCamera,
      dslrSidecar: networked[1],
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
        final usbPresent = _isAndroid() && await _usbDevicePresent();
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
          final usbPresent = await _usbDevicePresent();
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

  Future<KioskDeviceStatusEntry> _probeSelphyPrinter() async {
    if (_isWeb() || !_isAndroid()) {
      return const KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceSelphyPrinter,
        connected: false,
        transport: KioskDeviceTransport.usb,
      );
    }
    try {
      final result = await _selphy.probe().timeout(_wifiDiscoverTimeout);
      final transport = result.transport == 'wifi'
          ? KioskDeviceTransport.wifi
          : KioskDeviceTransport.usb;
      return KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceSelphyPrinter,
        connected: result.connected,
        transport: transport,
      );
    } on TimeoutException {
      return const KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceSelphyPrinter,
        connected: false,
        transport: KioskDeviceTransport.usb,
      );
    } catch (_) {
      return const KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceSelphyPrinter,
        connected: false,
        transport: KioskDeviceTransport.usb,
      );
    }
  }

  Future<bool> _usbDevicePresent() async {
    try {
      return await _usb.probeDevicePresent().timeout(_wifiDiscoverTimeout);
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _probeDnpWifi(AppSettingsModel? settings) async {
    if (kIsWeb) return false;
    try {
      final cached = _wifi.printerBaseUrl;
      if (cached != null && cached.trim().isNotEmpty) return true;

      final configured = resolvePrinterEndpoint(settings);
      if (configured.host.isNotEmpty) {
        return _wifi.probeBaseUrl(configured.baseUrl).timeout(
              _wifiDiscoverTimeout,
            );
      }

      final url = await _wifi
          .discover(parallelism: 32)
          .timeout(_wifiDiscoverTimeout);
      return url != null && url.trim().isNotEmpty;
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
    try {
      final present = await _probeUvcDevices().timeout(_wifiDiscoverTimeout);
      return KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceUsbCamera,
        connected: present,
        transport: KioskDeviceTransport.usb,
      );
    } on TimeoutException {
      return const KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceUsbCamera,
        connected: false,
        transport: KioskDeviceTransport.usb,
      );
    } catch (_) {
      return const KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceUsbCamera,
        connected: false,
        transport: KioskDeviceTransport.usb,
      );
    }
  }

  Future<KioskDeviceStatusEntry> _probeDslrCamera(
    AppSettingsModel? settings,
  ) async {
    final config = resolveCameraSidecarConfig(settings);
    final transport = config.isPiConnection
        ? KioskDeviceTransport.lan
        : KioskDeviceTransport.usb;

    // Native PTP disables the HTTP sidecar but still owns USB — do not show
    // "Not configured" on a working direct-PTP booth.
    if (config.isDirectPtpConnection) {
      final cameraPresent = await _safeCanonCameraPresent();
      return KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceDslrSidecar,
        connected: cameraPresent,
        configured: true,
        transport: KioskDeviceTransport.usb,
      );
    }

    if (!config.isConfigured) {
      return KioskDeviceStatusEntry(
        deviceName: AppStrings.kioskDeviceDslrSidecar,
        connected: false,
        configured: false,
        transport: transport,
      );
    }

    // Direct USB: native presence + health. Pi: HTTP health is enough.
    final cameraPresentFuture = config.isDirectConnection
        ? _safeCanonCameraPresent()
        : Future<bool>.value(false);
    final healthFuture = _safeDslrHealth(config);
    final nativeStateFuture = config.isDirectConnection
        ? _safeSidecarNativeState()
        : Future<String?>.value(null);

    final cameraPresent = await cameraPresentFuture;
    final httpHealthy = await healthFuture;
    final nativeState = await nativeStateFuture;

    // Direct: connected when Canon is on USB **or** localhost EDSDK is serving
    // EVF (USB list can be empty while the sidecar holds the interface).
    // Pi: connected = sidecar /health ok.
    // Only max_restarts is a terminal red state — a single `crashed` is the
    // normal gap before CanonSidecarRuntime relaunches (3s).
    final crashed = config.isDirectConnection &&
        !httpHealthy &&
        nativeState == 'max_restarts';
    final sidecarServing = httpHealthy ||
        nativeState == 'running' ||
        nativeState == 'waiting_usb';
    final connected = config.isDirectConnection
        ? (cameraPresent || sidecarServing)
        : httpHealthy;

    return KioskDeviceStatusEntry(
      deviceName: AppStrings.kioskDeviceDslrSidecar,
      connected: connected,
      configured: true,
      crashed: crashed,
      transport: transport,
    );
  }

  Future<bool> _safeCanonCameraPresent() async {
    try {
      return await _queryCanonCameraPresent()
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _safeDslrHealth(CameraSidecarConfig config) async {
    try {
      return await _probeDslrSidecar(config).timeout(_wifiDiscoverTimeout);
    } catch (_) {
      return false;
    }
  }

  Future<String> _safeSidecarNativeState() async {
    try {
      return await _querySidecarNativeState()
          .timeout(const Duration(seconds: 1), onTimeout: () => 'idle');
    } catch (_) {
      return 'idle';
    }
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

  @visibleForTesting
  static Future<bool> defaultDslrSidecarProbeForTesting(
    CameraSidecarConfig config,
  ) =>
      _defaultDslrSidecarProbe(config);

  static Future<bool> _defaultDslrSidecarProbe(CameraSidecarConfig config) async {
    final service = LocalCameraService(config: config);
    try {
      return await service.isHealthy();
    } finally {
      service.dispose();
    }
  }
}
