import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/capture_sound_service.dart';

void main() {
  group('CaptureSoundService', () {
    test('disabled service no-ops without throwing', () async {
      final service = CaptureSoundService(enabled: false);
      await service.warmUp();
      await service.playShutter();
      await service.cancel();
      await service.dispose();
    });

    test('dispose without warmUp does not touch platform audio', () async {
      final service = CaptureSoundService();
      await service.dispose();
    });

    test('shutter volume is full', () {
      expect(CaptureSoundService(enabled: false).enabled, isFalse);
      expect(CaptureSoundService.shutterVolume, 1.0);
    });
  });
}
