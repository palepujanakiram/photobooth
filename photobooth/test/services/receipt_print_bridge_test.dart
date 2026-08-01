import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/services/receipt/receipt_print_bridge.dart';
import 'package:photobooth/services/receipt/receipt_usb_client.dart';
import 'package:photobooth/services/receipt/receipt_wifi_client.dart';
import 'package:photobooth/services/receipt_printer_service_io.dart';
import 'package:photobooth/utils/exceptions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReceiptPrintBridge', () {
    test('deliverEscPos uses USB when device present on Android', () async {
      var usbSent = false;
      final bridge = ReceiptPrintBridge(
        isAndroid: () => true,
        usbClient: _RecordingUsbClient(
          present: true,
          onSend: () => usbSent = true,
        ),
        wifiClient: ReceiptWifiClient(),
        lanService: _FakeLanService(onSend: (_, __, ___) async {
          fail('LAN should not be used when USB succeeds');
        }),
        prepareWifiNetwork: () async => true,
      );

      await bridge.deliverEscPos(
        bytes: Uint8List.fromList([1, 2, 3]),
        settings: AppSettingsModel(receiptPrinterEnabled: true),
      );
      expect(usbSent, isTrue);
    });

    test('deliverEscPos discovers Wi-Fi when USB absent', () async {
      String? lanHost;
      final bridge = ReceiptPrintBridge(
        isAndroid: () => true,
        usbClient: _FakeReceiptUsbClient(present: false),
        wifiClient: ReceiptWifiClient(
          discoverFn: ({int parallelism = 20}) async => '192.168.0.77',
        ),
        lanService: _FakeLanService(
          onSend: (host, port, bytes) async {
            lanHost = host;
            expect(port, 9100);
            expect(bytes, Uint8List.fromList([9]));
          },
        ),
        prepareWifiNetwork: () async => true,
      );

      await bridge.deliverEscPos(
        bytes: Uint8List.fromList([9]),
        settings: AppSettingsModel(receiptPrinterEnabled: true),
      );
      expect(lanHost, '192.168.0.77');
    });

    test('deliverEscPos falls back to settings host after discovery miss', () async {
      String? lanHost;
      final bridge = ReceiptPrintBridge(
        isAndroid: () => false,
        wifiClient: ReceiptWifiClient(
          discoverFn: ({int parallelism = 20}) async => null,
        ),
        lanService: _FakeLanService(
          onSend: (host, _, __) async => lanHost = host,
        ),
        prepareWifiNetwork: () async => true,
      );

      await bridge.deliverEscPos(
        bytes: Uint8List.fromList([1]),
        settings: AppSettingsModel(
          receiptPrinterEnabled: true,
          receiptPrinterHost: '192.168.1.99',
        ),
      );
      expect(lanHost, '192.168.1.99');
    });

    test('deliverEscPos prefers API host over settings when discovery misses', () async {
      String? lanHost;
      final bridge = ReceiptPrintBridge(
        isAndroid: () => false,
        wifiClient: ReceiptWifiClient(
          discoverFn: ({int parallelism = 20}) async => null,
        ),
        lanService: _FakeLanService(
          onSend: (host, _, __) async => lanHost = host,
        ),
        prepareWifiNetwork: () async => true,
      );

      await bridge.deliverEscPos(
        bytes: Uint8List.fromList([1]),
        settings: AppSettingsModel(
          receiptPrinterEnabled: true,
          receiptPrinterHost: '192.168.1.99',
        ),
        apiHost: '192.168.1.50',
      );
      expect(lanHost, '192.168.1.50');
    });

    test('deliverEscPos throws when no printer path resolves', () async {
      final bridge = ReceiptPrintBridge(
        isAndroid: () => false,
        wifiClient: ReceiptWifiClient(
          discoverFn: ({int parallelism = 20}) async => null,
        ),
        lanService: _FakeLanService(onSend: (_, __, ___) async {}),
        prepareWifiNetwork: () async => true,
      );

      expect(
        () => bridge.deliverEscPos(
          bytes: Uint8List.fromList([1]),
          settings: AppSettingsModel(receiptPrinterEnabled: true),
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('probe reports USB when device present', () async {
      final bridge = ReceiptPrintBridge(
        isAndroid: () => true,
        usbClient: _FakeReceiptUsbClient(present: true),
        prepareWifiNetwork: () async => true,
      );
      final result = await bridge.probe(
        settings: AppSettingsModel(receiptPrinterEnabled: true),
      );
      expect(result.connected, isTrue);
      expect(result.transport, ReceiptPrinterTransport.usb);
    });

    test('USB failure falls back to Wi-Fi discovery', () async {
      String? lanHost;
      final bridge = ReceiptPrintBridge(
        isAndroid: () => true,
        usbClient: _FailingUsbClient(present: true),
        wifiClient: ReceiptWifiClient(
          discoverFn: ({int parallelism = 20}) async => '192.168.0.15',
        ),
        lanService: _FakeLanService(
          onSend: (host, _, __) async => lanHost = host,
        ),
        prepareWifiNetwork: () async => true,
      );

      await bridge.deliverEscPos(
        bytes: Uint8List.fromList([5]),
        settings: AppSettingsModel(receiptPrinterEnabled: true),
      );
      expect(lanHost, '192.168.0.15');
    });

    test('deliverEscPos throws on empty payload', () async {
      final bridge = ReceiptPrintBridge(
        isAndroid: () => false,
        lanService: _FakeLanService(onSend: (_, __, ___) async {}),
      );
      expect(
        () => bridge.deliverEscPos(bytes: Uint8List(0)),
        throwsA(isA<ApiException>()),
      );
    });

    test('deliverEscPos throws when USB error is not recoverable', () async {
      final bridge = ReceiptPrintBridge(
        isAndroid: () => true,
        usbClient: _NonRecoverableUsbClient(present: true),
        lanService: _FakeLanService(onSend: (_, __, ___) async {
          fail('LAN should not run');
        }),
      );
      expect(
        () => bridge.deliverEscPos(
          bytes: Uint8List.fromList([1]),
          settings: AppSettingsModel(receiptPrinterEnabled: true),
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('deliverEscPos uses cached Wi-Fi host without rediscovering', () async {
      String? lanHost;
      final wifi = ReceiptWifiClient()..hostForTesting = '192.168.0.99';
      final bridge = ReceiptPrintBridge(
        isAndroid: () => false,
        wifiClient: wifi,
        lanService: _FakeLanService(onSend: (host, _, __) async => lanHost = host),
      );
      await bridge.deliverEscPos(bytes: Uint8List.fromList([1]));
      expect(lanHost, '192.168.0.99');
    });

    test('resetSession clears USB ready state', () async {
      var connectCalls = 0;
      final bridge = ReceiptPrintBridge(
        isAndroid: () => true,
        usbClient: _ConnectCountingUsbClient(
          present: true,
          onConnect: () => connectCalls++,
        ),
        lanService: _FakeLanService(onSend: (_, __, ___) async {}),
      );
      await bridge.deliverEscPos(bytes: Uint8List.fromList([1]));
      await bridge.deliverEscPos(bytes: Uint8List.fromList([2]));
      expect(connectCalls, 1);
      bridge.resetSession();
      await bridge.deliverEscPos(bytes: Uint8List.fromList([3]));
      expect(connectCalls, 2);
    });

    test('probeUsbPresent delegates to USB client', () async {
      final bridge = ReceiptPrintBridge(
        isAndroid: () => true,
        usbClient: _FakeReceiptUsbClient(present: true),
      );
      expect(await bridge.probeUsbPresent(), isTrue);
    });

    test('probe reports Wi-Fi discovery result', () async {
      final bridge = ReceiptPrintBridge(
        isAndroid: () => false,
        wifiClient: ReceiptWifiClient(
          discoverFn: ({int parallelism = 20}) async => '192.168.0.44',
        ),
        prepareWifiNetwork: () async => true,
      );
      final result = await bridge.probe(
        settings: AppSettingsModel(receiptPrinterEnabled: true),
      );
      expect(result.connected, isTrue);
      expect(result.transport, ReceiptPrinterTransport.wifi);
      expect(result.host, '192.168.0.44');
    });

    test('probe uses configured host when discovery misses', () async {
      final bridge = ReceiptPrintBridge(
        isAndroid: () => false,
        wifiClient: ReceiptWifiClient(
          discoverFn: ({int parallelism = 20}) async => null,
          probeFn: (host, port) async => host == '192.168.1.77',
        ),
        prepareWifiNetwork: () async => true,
      );
      final result = await bridge.probe(
        settings: AppSettingsModel(
          receiptPrinterEnabled: true,
          receiptPrinterHost: '192.168.1.77',
        ),
      );
      expect(result.connected, isTrue);
      expect(result.host, '192.168.1.77');
    });

    test('probe reports disconnected when nothing configured', () async {
      final bridge = ReceiptPrintBridge(
        isAndroid: () => false,
        wifiClient: ReceiptWifiClient(
          discoverFn: ({int parallelism = 20}) async => null,
        ),
      );
      final result = await bridge.probe(
        settings: AppSettingsModel(receiptPrinterEnabled: true),
      );
      expect(result.connected, isFalse);
      expect(result.configured, isFalse);
    });

    test('Wi-Fi bind failure skips discovery and uses settings host', () async {
      String? lanHost;
      final bridge = ReceiptPrintBridge(
        isAndroid: () => true,
        usbClient: _FakeReceiptUsbClient(present: false),
        wifiClient: ReceiptWifiClient(
          discoverFn: ({int parallelism = 20}) async => '192.168.0.88',
        ),
        lanService: _FakeLanService(onSend: (host, _, __) async => lanHost = host),
        prepareWifiNetwork: () async => false,
      );
      await bridge.deliverEscPos(
        bytes: Uint8List.fromList([1]),
        settings: AppSettingsModel(
          receiptPrinterEnabled: true,
          receiptPrinterHost: '192.168.1.20',
        ),
      );
      expect(lanHost, '192.168.1.20');
    });

    test('default isAndroid path skips USB on non-Android hosts', () async {
      String? lanHost;
      final bridge = ReceiptPrintBridge(
        wifiClient: ReceiptWifiClient()..hostForTesting = '192.168.0.55',
        lanService: _FakeLanService(onSend: (host, _, __) async => lanHost = host),
      );
      await bridge.deliverEscPos(bytes: Uint8List.fromList([1]));
      expect(lanHost, '192.168.0.55');
    });
  });
}

class _FakeReceiptUsbClient extends ReceiptUsbClient {
  _FakeReceiptUsbClient({required this.present});

  final bool present;

  @override
  Future<bool> probeDevicePresent() async => present;

  @override
  Future<void> ensureConnected() async {}

  @override
  Future<void> sendEscPos(Uint8List bytes) async {}
}

class _RecordingUsbClient extends ReceiptUsbClient {
  _RecordingUsbClient({required this.present, required this.onSend});

  final bool present;
  final VoidCallback onSend;

  @override
  Future<bool> probeDevicePresent() async => present;

  @override
  Future<void> ensureConnected() async {}

  @override
  Future<void> sendEscPos(Uint8List bytes) async => onSend();
}

class _FailingUsbClient extends ReceiptUsbClient {
  _FailingUsbClient({required this.present});

  final bool present;

  @override
  Future<bool> probeDevicePresent() async => present;

  @override
  Future<void> ensureConnected() async {
    throw PlatformException(code: 'CONNECT_FAILED', message: 'USB failed');
  }
}

class _NonRecoverableUsbClient extends ReceiptUsbClient {
  _NonRecoverableUsbClient({required this.present});

  final bool present;

  @override
  Future<bool> probeDevicePresent() async => present;

  @override
  Future<void> ensureConnected() async {
    throw PlatformException(code: 'INVALID_ARG', message: 'bad args');
  }
}

class _ConnectCountingUsbClient extends ReceiptUsbClient {
  _ConnectCountingUsbClient({required this.present, required this.onConnect});

  final bool present;
  final VoidCallback onConnect;

  @override
  Future<bool> probeDevicePresent() async => present;

  @override
  Future<void> ensureConnected() async => onConnect();

  @override
  Future<void> sendEscPos(Uint8List bytes) async {}
}

class _FakeLanService extends ReceiptPrinterService {
  _FakeLanService({required this.onSend});

  final Future<void> Function(String host, int port, Uint8List bytes) onSend;

  @override
  Future<void> sendEscPosBytes({
    required String host,
    required int port,
    required Uint8List bytes,
  }) =>
      onSend(host, port, bytes);
}
