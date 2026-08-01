import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/receipt/receipt_wifi_client.dart';

void main() {
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

    test('clear resets cached host', () {
      final client = ReceiptWifiClient()..hostForTesting = '10.0.0.5';
      client.clear();
      expect(client.host, isNull);
    });
  });
}
