import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/camera_image_yuv_jpeg.dart';

void main() {
  CameraImage yuv2x2() {
    return CameraImage.fromPlatformData({
      'format': 35,
      'height': 2,
      'width': 2,
      'planes': [
        {
          'bytes': Uint8List.fromList([100, 110, 120, 130]),
          'bytesPerRow': 2,
          'bytesPerPixel': 1,
        },
        {
          'bytes': Uint8List.fromList([128]),
          'bytesPerRow': 1,
          'bytesPerPixel': 1,
        },
        {
          'bytes': Uint8List.fromList([128]),
          'bytesPerRow': 1,
          'bytesPerPixel': 1,
        },
      ],
    });
  }

  test('cameraImageToJpegBytes encodes YUV420 image', () {
    final jpeg = cameraImageToJpegBytes(yuv2x2());
    expect(jpeg, isNotEmpty);
    expect(jpeg[0], 0xFF);
    expect(jpeg[1], 0xD8);
  });

  test('cameraImageToJpegBytes throws when fewer than 3 planes', () {
    final bad = CameraImage.fromPlatformData({
      'format': 35,
      'height': 2,
      'width': 2,
      'planes': [
        {
          'bytes': Uint8List(4),
          'bytesPerRow': 2,
          'bytesPerPixel': 1,
        },
        {
          'bytes': Uint8List(1),
          'bytesPerRow': 1,
          'bytesPerPixel': 1,
        },
      ],
    });
    expect(
      () => cameraImageToJpegBytes(bad),
      throwsA(isA<Exception>()),
    );
  });
}
