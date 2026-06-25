import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/face_count_service.dart';

void main() {
  group('detectFaceCountFromXFile', () {
    test('returns 0 for empty path on VM (no mobile platform channel)', () async {
      final count = await detectFaceCountFromXFile(XFile(''));
      expect(count, 0);
    });

    test('returns 0 for missing file on VM', () async {
      final count = await detectFaceCountFromXFile(
        XFile('/nonexistent/face_count_test.jpg'),
      );
      expect(count, 0);
    });
  });
}
