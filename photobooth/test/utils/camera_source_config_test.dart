import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/app_settings_model.dart';
import 'package:photobooth/utils/camera_source_config.dart';

void main() {
  group('cameraSourceFromName', () {
    test('parses the canonical names', () {
      expect(cameraSourceFromName('device'), CameraSource.device);
      expect(cameraSourceFromName('uvc'), CameraSource.uvc);
      expect(cameraSourceFromName('sidecar'), CameraSource.sidecar);
      expect(cameraSourceFromName('direct_ptp'), CameraSource.directPtp);
    });

    test('accepts the aliases an operator is likely to type', () {
      expect(cameraSourceFromName('dslr'), CameraSource.directPtp);
      expect(cameraSourceFromName('ptp'), CameraSource.directPtp);
      expect(cameraSourceFromName('directPtp'), CameraSource.directPtp);
      expect(cameraSourceFromName('direct-ptp'), CameraSource.directPtp);
      expect(cameraSourceFromName('hdmi'), CameraSource.uvc);
      expect(cameraSourceFromName('pi'), CameraSource.sidecar);
    });

    test('is case and whitespace insensitive', () {
      expect(cameraSourceFromName('  DIRECT_PTP  '), CameraSource.directPtp);
      expect(cameraSourceFromName('Uvc'), CameraSource.uvc);
    });

    test('an unknown value falls back rather than throwing', () {
      // This can arrive from remote kiosk settings. A typo there should leave
      // the booth shooting on its default camera, not refuse to start an event.
      expect(cameraSourceFromName('nonsense'), CameraSource.device);
      expect(cameraSourceFromName(null), CameraSource.device);
      expect(cameraSourceFromName(''), CameraSource.device);
    });

    test('honours an explicit fallback', () {
      expect(
        cameraSourceFromName('nonsense', fallback: CameraSource.uvc),
        CameraSource.uvc,
      );
    });
  });

  group('isDslr', () {
    test('is true only for the tethered-camera sources', () {
      expect(CameraSource.sidecar.isDslr, isTrue);
      expect(CameraSource.directPtp.isDslr, isTrue);
      expect(CameraSource.device.isDslr, isFalse);
      expect(CameraSource.uvc.isDslr, isFalse);
    });
  });

  group('resolveCameraSource', () {
    test('defaults to the device camera when nothing is configured', () {
      // Existing builds must be unaffected by the direct-PTP work.
      expect(resolveCameraSource(overrideDefine: ''), CameraSource.device);
      expect(resolveCameraSource(overrideDefine: '   '), CameraSource.device);
    });

    test('selects direct PTP when configured', () {
      expect(
        resolveCameraSource(overrideDefine: 'direct_ptp'),
        CameraSource.directPtp,
      );
    });

    test('an unrecognised define does not silently disable the camera', () {
      expect(resolveCameraSource(overrideDefine: 'typo'), CameraSource.device);
    });
  });

  group('usesDirectPtpCamera', () {
    test('honours ZenAI cameraConnectionMode=direct_ptp', () {
      expect(
        usesDirectPtpCamera(
          settings: AppSettingsModel(cameraConnectionMode: 'direct_ptp'),
          overrideSourceDefine: '',
        ),
        isTrue,
      );
    });

    test('explicit pi/direct never opens PTP even with CAMERA_SOURCE', () {
      expect(
        usesDirectPtpCamera(
          settings: AppSettingsModel(cameraConnectionMode: 'pi'),
          overrideSourceDefine: 'direct_ptp',
        ),
        isFalse,
      );
      expect(
        usesDirectPtpCamera(
          settings: AppSettingsModel(cameraConnectionMode: 'direct'),
          overrideSourceDefine: 'direct_ptp',
        ),
        isFalse,
      );
    });

    test('falls back to CAMERA_SOURCE when mode is unset', () {
      expect(
        usesDirectPtpCamera(
          settings: AppSettingsModel(),
          overrideSourceDefine: 'direct_ptp',
          overrideConnectionModeDefine: '',
        ),
        isTrue,
      );
    });

    test('honours CAMERA_CONNECTION_MODE=direct_ptp without ZenAI mode', () {
      expect(
        usesDirectPtpCamera(
          settings: AppSettingsModel(),
          overrideSourceDefine: '',
          overrideConnectionModeDefine: 'direct_ptp',
        ),
        isTrue,
      );
    });

    test('explicit dart-define pi/direct never opens PTP', () {
      expect(
        usesDirectPtpCamera(
          settings: AppSettingsModel(),
          overrideSourceDefine: 'direct_ptp',
          overrideConnectionModeDefine: 'pi',
        ),
        isFalse,
      );
      expect(
        usesDirectPtpCamera(
          settings: AppSettingsModel(),
          overrideSourceDefine: 'direct_ptp',
          overrideConnectionModeDefine: 'direct',
        ),
        isFalse,
      );
    });
  });
}
