import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/receipt/receipt_usb_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.srisarani.fotozenai/receipt_usb');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('ReceiptUsbClient', () {
    test('default constructor binds native receipt channel', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'hasUsbHost') return false;
        return null;
      });
      expect(await ReceiptUsbClient().hasUsbHost(), isFalse);
    });

    test('hasUsbHost returns false on web or non-Android', () async {
      final client = ReceiptUsbClient(isAndroid: () => false);
      expect(await client.hasUsbHost(), isFalse);
    });

    test('probeDevicePresent returns false when channel throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERR');
      });
      final client = ReceiptUsbClient(channel: channel, isAndroid: () => true);
      expect(await client.probeDevicePresent(), isFalse);
    });

    test('default constructor uses platform channel', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'probeDevice') return true;
        return null;
      });
      expect(await ReceiptUsbClient(isAndroid: () => true).probeDevicePresent(), isTrue);
    });

    test('hasUsbHost and probeDevicePresent succeed on Android', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'hasUsbHost') return true;
        if (call.method == 'probeDevice') return true;
        return null;
      });
      final client = ReceiptUsbClient(channel: channel, isAndroid: () => true);
      expect(await client.hasUsbHost(), isTrue);
      expect(await client.probeDevicePresent(), isTrue);
    });

    test('ensureConnected invokes requestPermission', () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      final client = ReceiptUsbClient(channel: channel, isAndroid: () => true);
      await client.ensureConnected();
      expect(calls, ['requestPermission']);
    });

    test('sendEscPos sends inline bytes for small payloads', () async {
      MethodCall? lastCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        lastCall = call;
        return null;
      });
      final client = ReceiptUsbClient(channel: channel, isAndroid: () => true);
      final bytes = Uint8List.fromList([1, 2, 3]);
      await client.sendEscPos(bytes);
      expect(lastCall?.method, 'sendEscPos');
      expect(lastCall?.arguments['bytes'], bytes);
    });

    test('sendEscPos uses file channel for large payloads', () async {
      const pathProviderChannel =
          MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
        if (call.method == 'getTemporaryDirectory') {
          return Directory.systemTemp.path;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, null);
      });

      MethodCall? lastCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        lastCall = call;
        return null;
      });
      final client = ReceiptUsbClient(
        channel: channel,
        isAndroid: () => true,
        inlinePayloadLimit: 4,
      );
      await client.sendEscPos(Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(lastCall?.method, 'sendEscPosFile');
      expect(lastCall?.arguments['filePath'], isNotEmpty);
    });
  });
}
