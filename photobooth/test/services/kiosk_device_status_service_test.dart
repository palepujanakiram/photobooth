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
import 'package:photobooth/utils/app_strings.dart';

void main() {
  group('KioskDeviceStatusService', () {
    test('USB DNP transport reports USB mode when device present', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
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

    test('wifi DNP falls back to configured printerHost after discovery', () async {
      var discoverCalled = false;
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
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
      expect(discoverCalled, isTrue);
    });

    test('wifi DNP transport uses WiFi discovery', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
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
        usbClient: _FakeUsbClient(present: false),
        receiptBridge: _FakeReceiptBridge(
          probeResult: const ReceiptPrinterProbeResult(
            connected: false,
            transport: ReceiptPrinterTransport.wifi,
            configured: false,
          ),
        ),
        probeUvcDevices: () async => true,
      );
      final snap = await service.probe(settings: AppSettingsModel());
      expect(snap.usbCamera.connected, isTrue);
      expect(snap.usbCamera.transport, KioskDeviceTransport.usb);
    });

    test('USB camera absent reports not connected', () async {
      final service = KioskDeviceStatusService(
        isAndroid: () => true,
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
      expect(snap.usbCamera.connected, isFalse);
    });
  });
}

class _FakeUsbClient extends DnpUsbClient {
  _FakeUsbClient({required this.present});

  final bool present;

  @override
  Future<bool> probeDevicePresent() async => present;

  @override
  Future<bool> hasUsbHost() async => present;
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
