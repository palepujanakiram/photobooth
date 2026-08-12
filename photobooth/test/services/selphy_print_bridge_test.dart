import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/selphy/selphy_client.dart';
import 'package:photobooth/services/selphy/selphy_print_bridge.dart';
import 'package:photobooth/services/selphy/selphy_print_size.dart';
import 'package:photobooth/utils/exceptions.dart';

class _FakeSelphyClient extends SelphyClient {
  _FakeSelphyClient() : super(isAndroid: () => true);

  bool usbPresent = false;
  bool usbConnectOk = true;
  bool wifiDiscoverOk = true;
  bool printOk = true;
  int printCalls = 0;
  int releaseWifiCalls = 0;
  int resetCalls = 0;
  String? lastTransport;
  String? lastPaperSize;
  int? lastCopies;
  PlatformException? printError;

  @override
  Future<bool> probeUsbPresent() async => usbPresent;

  @override
  Future<void> ensureUsbConnected() async {
    if (!usbConnectOk) {
      throw PlatformException(code: 'PERMISSION_DENIED');
    }
  }

  @override
  Future<void> discoverWifi() async {
    if (!wifiDiscoverOk) {
      throw PlatformException(code: 'NO_PRINTER', message: 'none');
    }
  }

  @override
  Future<void> releaseWifi() async {
    releaseWifiCalls++;
  }

  @override
  Future<void> resetSession() async {
    resetCalls++;
  }

  @override
  Future<void> print({
    required String filePath,
    required String transport,
    required String paperSize,
    required int copies,
    String filter = 'Off',
    int brightness = 0,
    bool bordered = false,
  }) async {
    if (printError != null) throw printError!;
    if (!printOk) {
      throw PlatformException(code: 'PRINT_ERROR', message: 'failed');
    }
    printCalls++;
    lastTransport = transport;
    lastPaperSize = paperSize;
    lastCopies = copies;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SelphyPrintSize', () {
    test('maps network tokens', () {
      expect(
        SelphyPrintSize.fromNetworkPrintSize('s4x6').paperSize,
        '4x6',
      );
      expect(
        SelphyPrintSize.fromNetworkPrintSize('L-size').paperSize,
        'L-size',
      );
      expect(
        SelphyPrintSize.fromNetworkPrintSize('card').paperSize,
        'Card',
      );
    });
  });

  group('SelphyPrintBridge', () {
    late Directory tempDir;
    late File imageFile;
    late _FakeSelphyClient client;
    late SelphyPrintBridge bridge;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('selphy_print_');
      imageFile = File('${tempDir.path}/photo.jpg');
      await imageFile.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
      client = _FakeSelphyClient();
      bridge = SelphyPrintBridge(client: client, isAndroid: () => true);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('probe reports USB when present', () async {
      client.usbPresent = true;
      final result = await bridge.probe();
      expect(result.connected, isTrue);
      expect(result.transport, 'usb');
      expect(client.releaseWifiCalls, 0);
    });

    test('probe falls back to WiFi and releases binding', () async {
      client.usbPresent = false;
      client.wifiDiscoverOk = true;
      final result = await bridge.probe();
      expect(result.connected, isTrue);
      expect(result.transport, 'wifi');
      expect(client.releaseWifiCalls, 1);
    });

    test('probe reports not connected when WiFi missing', () async {
      client.usbPresent = false;
      client.wifiDiscoverOk = false;
      final result = await bridge.probe();
      expect(result.connected, isFalse);
      expect(result.transport, 'wifi');
      expect(client.releaseWifiCalls, 1);
    });

    test('prints via USB when present', () async {
      client.usbPresent = true;
      await bridge.printImage(
        imageFile: XFile(imageFile.path),
        networkPrintSize: 's4x6',
        quantity: 2,
      );
      expect(client.printCalls, 1);
      expect(client.lastTransport, 'usb');
      expect(client.lastPaperSize, '4x6');
      expect(client.lastCopies, 2);
    });

    test('falls back to WiFi when USB absent', () async {
      client.usbPresent = false;
      await bridge.printImage(
        imageFile: XFile(imageFile.path),
        networkPrintSize: 's4x6',
      );
      expect(client.printCalls, 1);
      expect(client.lastTransport, 'wifi');
      expect(client.releaseWifiCalls, 1);
    });

    test('resetSession clears client', () async {
      await bridge.resetSession();
      expect(client.resetCalls, 1);
    });

    test('rejects empty path', () async {
      expect(
        () => bridge.printImage(
          imageFile: XFile(''),
          networkPrintSize: 's4x6',
        ),
        throwsA(isA<PrintException>()),
      );
    });

    test('rejects missing file', () async {
      expect(
        () => bridge.printImage(
          imageFile: XFile('${tempDir.path}/missing.jpg'),
          networkPrintSize: 's4x6',
        ),
        throwsA(isA<PrintException>()),
      );
    });

    test('web unsupported', () async {
      final webBridge = SelphyPrintBridge(
        client: client,
        isAndroid: () => true,
        webUnsupported: true,
      );
      expect(
        () => webBridge.printImage(
          imageFile: XFile(imageFile.path),
          networkPrintSize: 's4x6',
        ),
        throwsA(isA<PrintException>()),
      );
    });

    test('falls back to WiFi when USB permission denied', () async {
      client.usbPresent = true;
      client.usbConnectOk = false;
      await bridge.printImage(
        imageFile: XFile(imageFile.path),
        networkPrintSize: 's4x6',
      );
      expect(client.printCalls, 1);
      expect(client.lastTransport, 'wifi');
    });

    test('rethrows non-recoverable USB print errors', () async {
      client.usbPresent = true;
      client.printError = PlatformException(code: 'PRINT_ERROR', message: 'jam');
      expect(
        () => bridge.printImage(
          imageFile: XFile(imageFile.path),
          networkPrintSize: 's4x6',
        ),
        throwsA(
          isA<PlatformException>().having((e) => e.code, 'code', 'PRINT_ERROR'),
        ),
      );
    });

    test('probe on non-Android returns disconnected', () async {
      final iosBridge = SelphyPrintBridge(
        client: client,
        isAndroid: () => false,
      );
      final result = await iosBridge.probe();
      expect(result.connected, isFalse);
    });

    test('printImage rejects non-Android', () async {
      final iosBridge = SelphyPrintBridge(
        client: client,
        isAndroid: () => false,
      );
      expect(
        () => iosBridge.printImage(
          imageFile: XFile(imageFile.path),
          networkPrintSize: 's4x6',
        ),
        throwsA(isA<PrintException>()),
      );
    });

    test('default constructors use platform defaults', () async {
      final defaultClient = SelphyClient();
      expect(defaultClient.isSupported, isFalse);
      final defaultBridge = SelphyPrintBridge();
      final probe = await defaultBridge.probe();
      expect(probe.connected, isFalse);
    });

    test('rejects remote http paths', () async {
      expect(
        () => bridge.printImage(
          imageFile: XFile('https://example.com/a.jpg'),
          networkPrintSize: 's4x6',
        ),
        throwsA(isA<PrintException>()),
      );
    });
  });
}
