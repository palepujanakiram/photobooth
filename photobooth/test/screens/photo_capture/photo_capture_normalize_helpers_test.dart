import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_normalize_helpers.dart';
import 'package:photobooth/utils/app_runtime_config.dart';
import 'package:photobooth/utils/image_helper.dart';
import 'package:photobooth/utils/uvc_capture_config.dart';

void main() {
  tearDown(() {
    AppRuntimeConfig.instance.applyFromSettings(AppSettingsModel());
  });

  group('captureNormalizeJpegQuality', () {
    test('Classic strip uses print JPEG quality for UVC and built-in', () {
      expect(
        captureNormalizeJpegQuality(
          isUvc: true,
          preferStripPrintQuality: true,
        ),
        kStripCapturedPhotoJpegQuality,
      );
      expect(
        captureNormalizeJpegQuality(
          isUvc: false,
          preferStripPrintQuality: true,
        ),
        kStripCapturedPhotoJpegQuality,
      );
    });

    test('non-strip UVC uses UVC default quality', () {
      expect(
        captureNormalizeJpegQuality(
          isUvc: true,
          preferStripPrintQuality: false,
        ),
        UvcCaptureConfig.normalizeJpegQuality,
      );
    });

    test('non-strip built-in leaves quality to ImageHelper default', () {
      expect(
        captureNormalizeJpegQuality(
          isUvc: false,
          preferStripPrintQuality: false,
        ),
        isNull,
      );
    });

    test('thermal relief wins over strip quality on UVC', () {
      AppRuntimeConfig.instance.applyFromSettings(
        AppSettingsModel(thermalSafeMode: true),
      );
      expect(
        captureNormalizeJpegQuality(
          isUvc: true,
          preferStripPrintQuality: true,
        ),
        UvcCaptureConfig.thermalNormalizeJpegQuality,
      );
    });
  });

  group('captureNormalizeMaxDimension', () {
    test('Classic strip uses 3840 for UVC and built-in', () {
      expect(
        captureNormalizeMaxDimension(
          isUvc: true,
          preferStripPrintQuality: true,
        ),
        kStripCapturedPhotoMaxDimension,
      );
      expect(
        captureNormalizeMaxDimension(
          isUvc: false,
          preferStripPrintQuality: true,
        ),
        kStripCapturedPhotoMaxDimension,
      );
    });

    test('non-strip UVC caps at 1920', () {
      expect(
        captureNormalizeMaxDimension(
          isUvc: true,
          preferStripPrintQuality: false,
        ),
        UvcCaptureConfig.normalizeMaxDimension,
      );
    });

    test('thermal relief wins over strip max dim on UVC', () {
      AppRuntimeConfig.instance.applyFromSettings(
        AppSettingsModel(thermalSafeMode: true),
      );
      expect(
        captureNormalizeMaxDimension(
          isUvc: true,
          preferStripPrintQuality: true,
        ),
        UvcCaptureConfig.thermalNormalizeMaxDimension,
      );
    });
  });
}
