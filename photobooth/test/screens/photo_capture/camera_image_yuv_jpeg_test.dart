import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth/screens/photo_capture/camera_image_yuv_jpeg.dart';

const _yuv420Format = CameraImageFormat(ImageFormatGroup.yuv420, raw: 35);

CameraImage yuv2x2() {
  return CameraImage.fromPlatformInterface(
    CameraImageData(
      format: _yuv420Format,
      height: 2,
      width: 2,
      planes: [
        CameraImagePlane(
          bytes: Uint8List.fromList([100, 110, 120, 130]),
          bytesPerRow: 2,
          bytesPerPixel: 1,
        ),
        CameraImagePlane(
          bytes: Uint8List.fromList([128]),
          bytesPerRow: 1,
          bytesPerPixel: 1,
        ),
        CameraImagePlane(
          bytes: Uint8List.fromList([128]),
          bytesPerRow: 1,
          bytesPerPixel: 1,
        ),
      ],
    ),
  );
}

/// U/V planes with different row and pixel strides (common on HDMI capture cards).
CameraImage yuv4x2MismatchedChromaStrides() {
  return CameraImage.fromPlatformInterface(
    CameraImageData(
      format: _yuv420Format,
      height: 2,
      width: 4,
      planes: [
        CameraImagePlane(
          bytes: Uint8List.fromList(List.filled(8, 128)),
          bytesPerRow: 4,
          bytesPerPixel: 1,
        ),
        CameraImagePlane(
          bytes: Uint8List.fromList([128, 128]),
          bytesPerRow: 2,
          bytesPerPixel: 1,
        ),
        CameraImagePlane(
          bytes: Uint8List.fromList([255, 0, 255, 0, 255, 0, 255, 0]),
          bytesPerRow: 4,
          bytesPerPixel: 2,
        ),
      ],
    ),
  );
}

void main() {
  test('cameraImageToJpegBytes encodes YUV420 image', () {
    final jpeg = cameraImageToJpegBytes(yuv2x2());
    expect(jpeg, isNotEmpty);
    expect(jpeg[0], 0xFF);
    expect(jpeg[1], 0xD8);
  });

  test('reads V samples using V plane stride when chroma layouts differ', () {
    final jpeg = cameraImageToJpegBytes(yuv4x2MismatchedChromaStrides());
    final decoded = img.decodeJpg(jpeg);
    expect(decoded, isNotNull);
    final pixel = decoded!.getPixel(2, 0);
    expect(pixel.r, greaterThan(200));
  });

  test('cameraImageToJpegBytes throws when fewer than 3 planes', () {
    final bad = CameraImage.fromPlatformInterface(
      CameraImageData(
        format: _yuv420Format,
        height: 2,
        width: 2,
        planes: [
          CameraImagePlane(
            bytes: Uint8List(4),
            bytesPerRow: 2,
            bytesPerPixel: 1,
          ),
          CameraImagePlane(
            bytes: Uint8List(1),
            bytesPerRow: 1,
            bytesPerPixel: 1,
          ),
        ],
      ),
    );
    expect(
      () => cameraImageToJpegBytes(bad),
      throwsA(isA<Exception>()),
    );
  });
}
