import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_uvc_raster_capture.dart';

void main() {
  testWidgets('rasterCaptureRepaintBoundary returns null without render tree',
      (tester) async {
    final key = GlobalKey();
    expect(await rasterCaptureRepaintBoundary(boundaryKey: key), isNull);
  });
}
