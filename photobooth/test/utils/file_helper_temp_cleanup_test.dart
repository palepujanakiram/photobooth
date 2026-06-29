import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/file_helper_temp_cleanup.dart';

void main() {
  group('shouldDeleteTempImageFileName', () {
    test('matches legacy capture prefixes', () {
      expect(shouldDeleteTempImageFileName('capture_123.jpg'), isTrue);
      expect(shouldDeleteTempImageFileName('photo_abc.png'), isTrue);
      expect(shouldDeleteTempImageFileName('upload_x.jpeg'), isTrue);
    });

    test('matches UVC and stream capture temp files', () {
      expect(
        shouldDeleteTempImageFileName('uvc_raster_1710000000.png'),
        isTrue,
      );
      expect(
        shouldDeleteTempImageFileName('streamcap_1710000000.jpg'),
        isTrue,
      );
    });

    test('ignores non-image and unrelated files', () {
      expect(shouldDeleteTempImageFileName('session.json'), isFalse);
      expect(shouldDeleteTempImageFileName('readme.txt'), isFalse);
      expect(shouldDeleteTempImageFileName('random_image.jpg'), isFalse);
    });
  });
}
