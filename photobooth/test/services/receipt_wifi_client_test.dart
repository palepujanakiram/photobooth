import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/receipt/receipt_wifi_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReceiptWifiClient', () {
    test('discover uses injected discoverFn', () async {
      final client = ReceiptWifiClient(
        discoverFn: ({int parallelism = 20}) async => '192.168.0.88',
      );
      final host = await client.discover();
      expect(host, '192.168.0.88');
      expect(client.host, '192.168.0.88');
    });

    test('discoverOnPrefix scans subnet with probeFn', () async {
      final client = ReceiptWifiClient(
        probeFn: (host, port) async => host == '10.0.0.42',
      );
      final host = await client.discoverOnPrefix('10.0.0', parallelism: 50);
      expect(host, '10.0.0.42');
    });

    test('probeHost returns false on probe failure', () async {
      final client = ReceiptWifiClient(
        probeFn: (_, __) async => false,
      );
      expect(await client.probeHost('10.0.0.1'), isFalse);
    });

    test('configure stores host and port', () {
      final client = ReceiptWifiClient();
      client.configure(host: '192.168.2.10', port: 9100);
      expect(client.host, '192.168.2.10');
      expect(client.port, 9100);
    });

    test('probeHost returns true when probe succeeds', () async {
      final client = ReceiptWifiClient(
        probeFn: (_, __) async => true,
      );
      expect(await client.probeHost('10.0.0.1'), isTrue);
    });

    test('configure ignores blank host', () {
      final client = ReceiptWifiClient()..configure(host: '  ');
      expect(client.host, isNull);
    });

    test('discover returns null when discoverFn returns null', () async {
      final client = ReceiptWifiClient(
        discoverFn: ({int parallelism = 20}) async => null,
      );
      expect(await client.discover(), isNull);
      expect(client.host, isNull);
    });

    test('discover returns null when local IP unavailable', () async {
      const networkInfoChannel =
          MethodChannel('dev.fluttercommunity.plus/network_info');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(networkInfoChannel, (call) async {
        if (call.method == 'wifiIPAddress') return '0.0.0.0';
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(networkInfoChannel, null);
      });

      final client = ReceiptWifiClient();
      expect(await client.discover(), isNull);
    });

    test('discover uses local Wi-Fi IP when discoverFn is absent', () async {
      const networkInfoChannel =
          MethodChannel('dev.fluttercommunity.plus/network_info');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(networkInfoChannel, (call) async {
        if (call.method == 'wifiIPAddress') return '192.168.5.100';
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(networkInfoChannel, null);
      });

      final client = ReceiptWifiClient(
        probeFn: (host, port) async => host == '192.168.5.120',
      );
      final host = await client.discover();
      expect(host, '192.168.5.120');
    });

    test('discover returns null when Wi-Fi IP is missing', () async {
      const networkInfoChannel =
          MethodChannel('dev.fluttercommunity.plus/network_info');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(networkInfoChannel, (call) async => null);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(networkInfoChannel, null);
      });

      final client = ReceiptWifiClient();
      expect(await client.discover(), isNull);
    });

    test('probeHost returns true when TCP connect succeeds', () async {
      final server = await ServerSocket.bind('127.0.0.1', 0);
      addTearDown(() async => server.close());
      final client = ReceiptWifiClient();
      expect(await client.probeHost('127.0.0.1', port: server.port), isTrue);
    });

    test('probeHost returns false when socket connect fails', () async {
      final client = ReceiptWifiClient();
      expect(await client.probeHost('192.0.2.1', port: 1), isFalse);
    });
  });
}
