import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/selphy/selphy_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'com.srisarani.fotozenai/selphy';

  group('SelphyClient', () {
    late MethodChannel channel;
    late SelphyClient client;
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      channel = const MethodChannel(channelName);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'probeUsb':
            return true;
          case 'requestPermission':
          case 'discoverWifi':
          case 'releaseWifi':
          case 'resetSession':
          case 'print':
            return 'ok';
          default:
            return null;
        }
      });
      client = SelphyClient(channel: channel, isAndroid: () => true);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('probeUsbPresent invokes channel', () async {
      expect(await client.probeUsbPresent(), isTrue);
      expect(calls.single.method, 'probeUsb');
    });

    test('ensureUsbConnected invokes requestPermission', () async {
      await client.ensureUsbConnected();
      expect(calls.single.method, 'requestPermission');
    });

    test('discoverWifi and releaseWifi', () async {
      await client.discoverWifi();
      await client.releaseWifi();
      expect(calls.map((c) => c.method), ['discoverWifi', 'releaseWifi']);
    });

    test('resetSession and print pass args', () async {
      await client.resetSession();
      await client.print(
        filePath: '/tmp/a.jpg',
        transport: 'usb',
        paperSize: '4x6',
        copies: 2,
      );
      expect(calls[0].method, 'resetSession');
      expect(calls[1].method, 'print');
      expect(calls[1].arguments['filePath'], '/tmp/a.jpg');
      expect(calls[1].arguments['transport'], 'usb');
      expect(calls[1].arguments['copies'], 2);
    });

    test('non-Android probe returns false without calling channel', () async {
      final ios = SelphyClient(channel: channel, isAndroid: () => false);
      expect(await ios.probeUsbPresent(), isFalse);
      expect(calls, isEmpty);
    });

    test('default isAndroid factory is exercised', () async {
      final defaultClient = SelphyClient(channel: channel);
      expect(defaultClient.isSupported, isFalse);
    });

    test('probeUsbPresent returns false when channel throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERR');
      });
      expect(await client.probeUsbPresent(), isFalse);
    });

    test('releaseWifi and resetSession swallow channel errors', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'ERR');
      });
      await client.releaseWifi();
      await client.resetSession();
    });
  });
}
