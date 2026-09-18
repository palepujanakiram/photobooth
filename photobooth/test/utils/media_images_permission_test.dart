import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photobooth/utils/media_images_permission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveMediaImagesPermission', () {
    test('Android 13 and above uses READ_MEDIA_IMAGES', () async {
      expect(
        await resolveMediaImagesPermission(androidSdkOverride: 33),
        Permission.photos,
      );
      expect(
        await resolveMediaImagesPermission(androidSdkOverride: 34),
        Permission.photos,
      );
    });

    test('below Android 13 uses the storage permission', () async {
      // READ_MEDIA_IMAGES does not exist there, and asking for it resolves
      // without showing anything — the dead "Grant access" button.
      for (final sdk in <int>[29, 30, 31, 32]) {
        expect(
          await resolveMediaImagesPermission(androidSdkOverride: sdk),
          Permission.storage,
          reason: 'SDK $sdk',
        );
      }
    });

    test('the boundary is exactly SDK 33', () async {
      expect(
        await resolveMediaImagesPermission(androidSdkOverride: kReadMediaImagesSdk - 1),
        Permission.storage,
      );
      expect(
        await resolveMediaImagesPermission(androidSdkOverride: kReadMediaImagesSdk),
        Permission.photos,
      );
    });
  });

  test('a host that is not Android answers for iOS, which has no split',
      () async {
    // No override: this runs on the test host, which is not Android.
    expect(await resolveMediaImagesPermission(), Permission.photos);
  });
}
