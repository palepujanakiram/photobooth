import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/sidecar_error_parse.dart';

void main() {
  group('parseSidecarError', () {
    test('extracts status, code, and edsError hex', () {
      final info = parseSidecarError(
        StateError(
          'Camera sidecar capture failed (502): '
          '{"ok":false,"error":"Failed to open camera session edsError=0x80",'
          '"code":"EDSDK_CMD_FAILED"}',
        ),
      );
      expect(info.statusCode, 502);
      expect(info.code, 'EDSDK_CMD_FAILED');
      expect(info.edsError, 0x80);
      expect(info.edsErrorHex, '0x80');
      expect(info.toDetail()['edsError'], 0x80);
    });

    test('extracts bare NO_CAMERA', () {
      final info = parseSidecarError(
        'No camera detected NO_CAMERA',
      );
      expect(info.code, 'NO_CAMERA');
    });

    test('extracts cooldown code', () {
      final info = parseSidecarError(
        'Camera session cooldown (4s) EDSDK_OPEN_COOLDOWN',
      );
      expect(info.code, 'EDSDK_OPEN_COOLDOWN');
    });

    test('extracts decimal edsError when hex is absent', () {
      final info = parseSidecarError('capture failed edsError=128');
      expect(info.edsError, 128);
      expect(info.edsErrorHex, '0x80');
    });
  });
}
