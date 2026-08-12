import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/models/kiosk_device_status.dart';
import 'package:photobooth/services/dnp/dnp_usb_client.dart';
import 'package:photobooth/services/dnp/dnp_wifi_client.dart';
import 'package:photobooth/services/kiosk_device_status_service.dart';
import 'package:photobooth/services/receipt/receipt_print_bridge.dart';
import 'package:photobooth/services/receipt/receipt_usb_client.dart';
import 'package:photobooth/services/receipt/receipt_wifi_client.dart';
import 'package:photobooth/services/selphy/selphy_print_bridge.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/camera_sidecar_config.dart';

void main() {
  group('KioskDeviceStatusService', () {
    test('USB DNP transport reports USB mode when device present', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: true),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(printerTransport: 'usb'),
      );
      expect(snap.dnpPrinter.connected, isTrue);
      expect(snap.dnpPrinter.transport, KioskDeviceTransport.usb);
      expect(snap.dnpPrinter.deviceName, AppStrings.kioskDeviceDnpPrinter);
    });

    test('auto transport prefers USB when DNP visible on USB', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: true),
        wifiClient: DnpWifiClient(
          discoverFn: ({int parallelism = 20}) async => 'http://10.0.0.9',
        ),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(printerTransport: 'auto'),
      );
      expect(snap.dnpPrinter.connected, isTrue);
      expect(snap.dnpPrinter.transport, KioskDeviceTransport.usb);
    });

    test('wifi DNP probes configured printerHost without discovery', () async {
      var discoverCalled = false;
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        wifiClient: DnpWifiClient(
          client: MockClient((request) async {
            expect(request.url.host, '192.168.0.155');
            return http.Response('{}', 200);
          }),
          discoverFn: ({int parallelism = 20}) async {
            discoverCalled = true;
            return null;
          },
        ),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(
          printerTransport: 'wifi',
          printerHost: '192.168.0.155',
        ),
      );
      expect(snap.dnpPrinter.connected, isTrue);
      expect(snap.dnpPrinter.transport, KioskDeviceTransport.wifi);
      expect(discoverCalled, isFalse);
    });

    test('wifi DNP transport uses WiFi discovery', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        wifiClient: DnpWifiClient(
          discoverFn: ({int parallelism = 20}) async => 'http://10.0.0.9',
        ),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(printerTransport: 'wifi'),
      );
      expect(snap.dnpPrinter.connected, isTrue);
      expect(snap.dnpPrinter.transport, KioskDeviceTransport.wifi);
    });

    test('receipt printer not configured shows not configured', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: true,
            transport: ReceiptPrinterTransport.wifi,
            configured: true,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(receiptPrinterEnabled: false),
      );
      expect(snap.receiptPrinter.configured, isFalse);
      expect(snap.receiptPrinter.connected, isFalse);
      expect(snap.receiptPrinter.transport, KioskDeviceTransport.wifi);
    });

    test('receipt printer USB reports connected USB mode', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: true,
            transport: ReceiptPrinterTransport.usb,
            configured: true,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(receiptPrinterEnabled: true),
      );
      expect(snap.receiptPrinter.configured, isTrue);
      expect(snap.receiptPrinter.connected, isTrue);
      expect(snap.receiptPrinter.transport, KioskDeviceTransport.usb);
    });

    test('receipt printer Wi-Fi discovery reports WiFi mode', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: true,
            transport: ReceiptPrinterTransport.wifi,
            configured: true,
            host: '192.168.1.50',
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(receiptPrinterEnabled: true),
      );
      expect(snap.receiptPrinter.configured, isTrue);
      expect(snap.receiptPrinter.connected, isTrue);
      expect(snap.receiptPrinter.transport, KioskDeviceTransport.wifi);
    });

    test('default wifi transport reports WiFi when unset', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        wifiClient: DnpWifiClient(
          discoverFn: ({int parallelism = 20}) async => 'http://10.0.0.9',
        ),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(settings: AppSettingsModel());
      expect(snap.dnpPrinter.connected, isTrue);
      expect(snap.dnpPrinter.transport, KioskDeviceTransport.wifi);
    });

    test('auto transport falls back to WiFi when USB absent', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        wifiClient: DnpWifiClient(
          discoverFn: ({int parallelism = 20}) async => 'http://10.0.0.9',
        ),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(printerTransport: 'auto'),
      );
      expect(snap.dnpPrinter.connected, isTrue);
      expect(snap.dnpPrinter.transport, KioskDeviceTransport.wifi);
    });

    test('wifi DNP discovery timeout reports not connected', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        wifiClient: DnpWifiClient(
          discoverFn: ({int parallelism = 20}) async {
            await Future<void>.delayed(const Duration(seconds: 10));
            return 'http://10.0.0.9';
          },
        ),
        wifiDiscoverTimeout: const Duration(milliseconds: 50),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(printerTransport: 'wifi'),
      );
      expect(snap.dnpPrinter.connected, isFalse);
      expect(snap.dnpPrinter.transport, KioskDeviceTransport.wifi);
    });

    test('receipt printer enabled without host is configured', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: true,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(
          receiptPrinterEnabled: true,
          receiptPrinterHost: '  ',
        ),
      );
      expect(snap.receiptPrinter.configured, isTrue);
      expect(snap.receiptPrinter.connected, isFalse);
    });

    test('USB camera present reports connected USB', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => true,
        probeDslrSidecar: (_) async => false,
      );
      final snap = await service.probe(settings: AppSettingsModel());
      expect(snap.usbCamera.connected, isTrue);
      expect(snap.usbCamera.transport, KioskDeviceTransport.usb);
    });

    test('USB camera absent reports not connected', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
        probeDslrSidecar: (_) async => false,
      );
      final snap = await service.probe(settings: AppSettingsModel());
      expect(snap.usbCamera.connected, isFalse);
    });

    test('DSLR sidecar not configured when camera disabled in settings', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
        probeDslrSidecar: (_) async => true,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(
          cameraEnabled: false,
          cameraSidecarHost: '172.16.4.128',
          cameraSidecarPort: 8791,
        ),
      );
      expect(snap.dslrSidecar.configured, isFalse);
      expect(snap.dslrSidecar.connected, isFalse);
      expect(snap.dslrSidecar.deviceName, AppStrings.kioskDeviceDslrSidecar);
      expect(snap.dslrSidecar.transport, KioskDeviceTransport.lan);
    });

    test('DSLR sidecar connected when Pi health succeeds', () async {
      CameraSidecarConfig? seen;
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
        probeDslrSidecar: (config) async {
          seen = config;
          return true;
        },
      );
      final snap = await service.probe(
        settings: AppSettingsModel(
          cameraEnabled: true,
          cameraSidecarHost: '172.16.4.128',
          cameraSidecarPort: 8791,
        ),
      );
      expect(snap.dslrSidecar.configured, isTrue);
      expect(snap.dslrSidecar.connected, isTrue);
      expect(snap.dslrSidecar.transport, KioskDeviceTransport.lan);
      expect(seen?.baseUrl, 'http://172.16.4.128:8791');
      expect(seen?.isConfigured, isTrue);
    });

    test('DSLR sidecar not connected when Pi health fails', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
        probeDslrSidecar: (_) async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(
          cameraEnabled: true,
          cameraSidecarHost: '172.16.4.128',
          cameraSidecarPort: 8791,
        ),
      );
      expect(snap.dslrSidecar.configured, isTrue);
      expect(snap.dslrSidecar.connected, isFalse);
    });

    test('DSLR sidecar probe timeout reports not connected', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
        probeDslrSidecar: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return true;
        },
        wifiDiscoverTimeout: const Duration(milliseconds: 10),
      );
      final snap = await service.probe(
        settings: AppSettingsModel(
          cameraEnabled: true,
          cameraSidecarHost: '172.16.4.128',
          cameraSidecarPort: 8791,
        ),
      );
      expect(snap.dslrSidecar.configured, isTrue);
      expect(snap.dslrSidecar.connected, isFalse);
    });

    test('default DSLR probe returns false when sidecar disabled', () async {
      final ok =
          await KioskDeviceStatusService.defaultDslrSidecarProbeForTesting(
        const CameraSidecarConfig(
          enabled: false,
          baseUrl: 'http://172.16.4.128:8791',
        ),
      );
      expect(ok, isFalse);
    });

    test('receipt probe timeout reports disconnected configured printer', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _SlowReceiptBridge(
          delay: const Duration(seconds: 5),
        ),
        wifiDiscoverTimeout: const Duration(milliseconds: 20),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(receiptPrinterEnabled: true),
      );
      expect(snap.receiptPrinter.configured, isTrue);
      expect(snap.receiptPrinter.connected, isFalse);
    });

    test('receipt probe errors report disconnected configured printer', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _ErrorReceiptBridge(),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(receiptPrinterEnabled: true),
      );
      expect(snap.receiptPrinter.configured, isTrue);
      expect(snap.receiptPrinter.connected, isFalse);
    });

    test('wifi DNP uses cached printer URL without discovery', () async {
      var discoverCalled = false;
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        wifiClient: DnpWifiClient(
          discoverFn: ({int parallelism = 20}) async {
            discoverCalled = true;
            return null;
          },
        )..printerBaseUrlForTesting = 'http://10.0.0.8',
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(printerTransport: 'wifi'),
      );
      expect(snap.dnpPrinter.connected, isTrue);
      expect(discoverCalled, isFalse);
    });

    test('wifi DNP probes configured host when discovery misses', () async {
      var probedHost = '';
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        wifiClient: DnpWifiClient(
          client: MockClient((request) async {
            probedHost = request.url.host;
            return http.Response('{}', 200);
          }),
          discoverFn: ({int parallelism = 20}) async => null,
        ),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(
          printerTransport: 'wifi',
          printerHost: '192.168.0.200',
        ),
      );
      expect(snap.dnpPrinter.connected, isTrue);
      expect(probedHost, '192.168.0.200');
    });

    test('uses default service dependencies when not injected', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => false,
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(receiptPrinterEnabled: false),
      );
      expect(snap.receiptPrinter.configured, isFalse);
      expect(snap.selphyPrinter.connected, isFalse);
    });

    test('DNP USB probe timeout reports not connected', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _SlowUsbClient(delay: const Duration(seconds: 5)),
        wifiDiscoverTimeout: const Duration(milliseconds: 40),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(printerTransport: 'usb'),
      );
      expect(snap.dnpPrinter.connected, isFalse);
    });

    test('USB camera probe timeout reports not connected', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        wifiDiscoverTimeout: const Duration(milliseconds: 40),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async {
          await Future<void>.delayed(const Duration(seconds: 5));
          return true;
        },
      );
      final snap = await service.probe(settings: AppSettingsModel());
      expect(snap.usbCamera.connected, isFalse);
    });

    test('wifi DNP probe catches unexpected errors', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        wifiClient: DnpWifiClient(
          discoverFn: ({int parallelism = 20}) async {
            throw StateError('boom');
          },
        ),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(printerTransport: 'wifi'),
      );
      expect(snap.dnpPrinter.connected, isFalse);
    });

    test('web platform skips DNP hardware probe', () async {
      final service = KioskDeviceStatusService(
        isWeb: () => true,
        selphyBridge: _FakeSelphyBridge(),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(
        settings: AppSettingsModel(printerTransport: 'usb'),
      );
      expect(snap.dnpPrinter.connected, isFalse);
      expect(snap.dnpPrinter.transport, KioskDeviceTransport.wifi);
    });

    test('default UVC probe detects attached webcam', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('uvccamera/native');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'isSupported') return true;
        if (call.method == 'getDevices') {
          return {
            'cam1': {
              'name': 'Webcam',
              'deviceClass': 14,
              'deviceSubclass': 0,
              'vendorId': 0x046d,
              'productId': 0x0825,
            },
          };
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
      );
      final snap = await service.probe(settings: AppSettingsModel());
      expect(snap.usbCamera.connected, isTrue);
    });

    test('Selphy USB connected reports Canon Selphy USB row', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(connected: true, transport: 'usb'),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(settings: AppSettingsModel());
      expect(snap.selphyPrinter.connected, isTrue);
      expect(snap.selphyPrinter.transport, KioskDeviceTransport.usb);
      expect(snap.selphyPrinter.deviceName, AppStrings.kioskDeviceSelphyPrinter);
    });

    test('Selphy WiFi connected reports Canon Selphy WiFi row', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(connected: true, transport: 'wifi'),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(settings: AppSettingsModel());
      expect(snap.selphyPrinter.connected, isTrue);
      expect(snap.selphyPrinter.transport, KioskDeviceTransport.wifi);
    });

    test('Selphy not connected when probe finds nothing', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(connected: false),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(settings: AppSettingsModel());
      expect(snap.selphyPrinter.connected, isFalse);
      expect(snap.selphyPrinter.deviceName, AppStrings.kioskDeviceSelphyPrinter);
    });

    test('Selphy probe timeout reports not connected', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(
          connected: true,
          delay: const Duration(seconds: 5),
        ),
        wifiDiscoverTimeout: const Duration(milliseconds: 40),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(settings: AppSettingsModel());
      expect(snap.selphyPrinter.connected, isFalse);
    });

    test('Selphy probe error reports not connected', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
        selphyBridge: _FakeSelphyBridge(throwOnProbe: true),
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => false,
      );
      final snap = await service.probe(settings: AppSettingsModel());
      expect(snap.selphyPrinter.connected, isFalse);
    });
  });
}

class _FakeSelphyBridge extends SelphyPrintBridge {
  _FakeSelphyBridge({
    this.connected = false,
    this.transport = 'usb',
    this.delay,
    this.throwOnProbe = false,
  }) : super(isAndroid: () => true, webUnsupported: false);

  final bool connected;
  final String transport;
  final Duration? delay;
  final bool throwOnProbe;

  @override
  Future<({bool connected, String? transport})> probe() async {
    if (delay != null) await Future<void>.delayed(delay!);
    if (throwOnProbe) throw StateError('selphy probe failed');
    return (connected: connected, transport: transport);
  }
}

class _FakeUsbClient extends DnpUsbClient {
  _FakeUsbClient({required this.present});

  final bool present;

  @override
  Future<bool> probeDevicePresent() async => present;

  @override
  Future<bool> hasUsbHost() async => present;
}

class _SlowUsbClient extends DnpUsbClient {
  _SlowUsbClient({required this.delay});

  final Duration delay;

  @override
  Future<bool> probeDevicePresent() async {
    await Future<void>.delayed(delay);
    return true;
  }
}

class _FakeReceiptBridge extends ReceiptPrintBridge {
  _FakeReceiptBridge({required this.probeResult})
      : super(
          isAndroid: () => true,
          usbClient: _SilentReceiptUsbClient(),
          wifiClient: ReceiptWifiClient(),
          prepareWifiNetwork: () async => true,
        );

  final ReceiptPrinterProbeResult probeResult;

  @override
  Future<ReceiptPrinterProbeResult> probe({
    AppSettingsModel? settings,
  }) async =>
      probeResult;
}

class _SilentReceiptUsbClient extends ReceiptUsbClient {
  @override
  Future<bool> probeDevicePresent() async => false;
}

class _SlowReceiptBridge extends ReceiptPrintBridge {
  _SlowReceiptBridge({required this.delay})
      : super(
          isAndroid: () => true,
          usbClient: _SilentReceiptUsbClient(),
          wifiClient: ReceiptWifiClient(),
        );

  final Duration delay;

  @override
  Future<ReceiptPrinterProbeResult> probe({
    AppSettingsModel? settings,
  }) async {
    await Future<void>.delayed(delay);
    return const ReceiptPrinterProbeResult(
      connected: true,
      transport: ReceiptPrinterTransport.wifi,
      configured: true,
    );
  }
}

class _ErrorReceiptBridge extends ReceiptPrintBridge {
  _ErrorReceiptBridge()
      : super(
          isAndroid: () => true,
          usbClient: _SilentReceiptUsbClient(),
          wifiClient: ReceiptWifiClient(),
        );

  @override
  Future<ReceiptPrinterProbeResult> probe({
    AppSettingsModel? settings,
  }) async {
    throw StateError('probe failed');
  }
}
