import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/receipt_printer_service_io.dart';
import 'package:photobooth/utils/exceptions.dart';

void main() {
  test('sendEscPosBytes writes to a local TCP socket', () async {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final port = server.port;
    final received = <int>[];
    server.listen((client) {
      client.listen(received.addAll, onDone: () => client.close());
    });

    final service = ReceiptPrinterService(
      connectTimeout: const Duration(seconds: 2),
    );
    final payload = Uint8List.fromList([0x1B, 0x40, 0x0A]);

    await service.sendEscPosBytes(
      host: '127.0.0.1',
      port: port,
      bytes: payload,
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(received, payload);
    await server.close();
  });

  test('sendEscPosBase64 decodes and sends bytes', () async {
    final server = await ServerSocket.bind('127.0.0.1', 0);
    final port = server.port;
    final received = <int>[];
    server.listen((client) {
      client.listen(received.addAll, onDone: () => client.close());
    });

    final bytes = Uint8List.fromList([0x1B, 0x40]);
    await ReceiptPrinterService().sendEscPosBase64(
      host: '127.0.0.1',
      port: port,
      payloadBase64: base64Encode(bytes),
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(received, bytes);
    await server.close();
  });

  test('sendEscPosBytes rejects empty payload', () async {
    await expectLater(
      ReceiptPrinterService().sendEscPosBytes(
        host: '127.0.0.1',
        port: 9100,
        bytes: Uint8List(0),
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('sendEscPosBytes maps validation failures to ApiException', () async {
    await expectLater(
      ReceiptPrinterService().sendEscPosBytes(
        host: '   ',
        port: 9100,
        bytes: Uint8List.fromList([0x1B]),
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('sendEscPosBytes maps socket failures to ApiException', () async {
    await expectLater(
      ReceiptPrinterService(
        connectTimeout: const Duration(milliseconds: 200),
      ).sendEscPosBytes(
        host: '127.0.0.1',
        port: 1,
        bytes: Uint8List.fromList([0x1B]),
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('sendEscPosBytes maps generic failures to ApiException', () async {
    final service = ReceiptPrinterService();
    service.connectOverride = (_, __, ___) async {
      throw StateError('printer offline');
    };
    await expectLater(
      service.sendEscPosBytes(
        host: '127.0.0.1',
        port: 9100,
        bytes: Uint8List.fromList([0x1B]),
      ),
      throwsA(isA<ApiException>()),
    );
  });

  test('sendEscPosBytes rethrows ApiException from connect override', () async {
    final service = ReceiptPrinterService();
    service.connectOverride = (_, __, ___) async {
      throw ApiException('bad host');
    };
    await expectLater(
      service.sendEscPosBytes(
        host: '127.0.0.1',
        port: 9100,
        bytes: Uint8List.fromList([0x1B]),
      ),
      throwsA(
        isA<ApiException>().having((e) => e.message, 'message', 'bad host'),
      ),
    );
  });
}
