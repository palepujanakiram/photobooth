import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/uvc_capture_config.dart';
import 'package:uvccamera/uvccamera.dart';

void main() {
  test('UvcCaptureConfig uses balanced profile defaults', () {
    expect(UvcCaptureConfig.resolutionPreset, UvcCameraResolutionPreset.low);
    expect(UvcCaptureConfig.normalizeMaxDimension, 1536);
    expect(UvcCaptureConfig.normalizeJpegQuality, 85);
    expect(UvcCaptureConfig.uploadPrepDelay, const Duration(milliseconds: 300));
  });
}
