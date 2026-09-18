import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/event_device_cameras.dart';

void main() {
  test('phone runtimes name the built-in camera', () {
    expect(
      EventDeviceCameras.labelFor(isWeb: false),
      AppStrings.eventHubPhoneCamera,
    );
  });

  test('web names a webcam', () {
    expect(EventDeviceCameras.labelFor(isWeb: true), AppStrings.eventHubWebcam);
  });

  test('listNames returns injected ids', () async {
    expect(
      await EventDeviceCameras.listNames(enumerate: () async => ['0', '1']),
      ['0', '1'],
    );
  });

  test('listNames uses the camera plugin when nothing is injected', () async {
    expect(await EventDeviceCameras.listNames(), isA<List<String>>());
  });

  test('labelFor defaults to the current runtime', () {
    expect(EventDeviceCameras.labelFor(), AppStrings.eventHubPhoneCamera);
  });
}
