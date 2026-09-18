import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/event_pipeline_capabilities.dart';

void main() {
  test('web can capture with a webcam but not USB hardware', () {
    final caps = EventPipelineCapabilities.ofPlatform(isWeb: true);
    expect(caps.hasLocalLedger, isFalse);
    expect(caps.canImport, isFalse);
    expect(caps.canCapturePtp, isFalse);
    expect(caps.canCaptureDevice, isTrue);
    expect(caps.canCapture, isTrue);
    expect(caps.canPrintUsb, isFalse);
  });

  test('Android is the booth worker', () {
    final caps = EventPipelineCapabilities.ofPlatform(
      isWeb: false,
      platform: TargetPlatform.android,
    );
    expect(caps.hasLocalLedger, isTrue);
    expect(caps.canImportCard, isTrue);
    expect(caps.canCapturePtp, isTrue);
    expect(caps.canCaptureDevice, isTrue);
    expect(caps.canPrintUsb, isTrue);
  });

  test('iOS captures with the phone camera', () {
    final caps = EventPipelineCapabilities.ofPlatform(
      isWeb: false,
      platform: TargetPlatform.iOS,
    );
    expect(caps.hasLocalLedger, isTrue);
    expect(caps.canImport, isFalse);
    expect(caps.canCapturePtp, isFalse);
    expect(caps.canCaptureDevice, isTrue);
    expect(caps.canCapture, isTrue);
  });

  test('ofPlatform uses the current runtime when nothing is passed', () {
    final caps = EventPipelineCapabilities.ofPlatform();
    expect(caps.canCaptureDevice, isTrue);
  });

  test('named constructors match the two roles', () {
    expect(const EventPipelineCapabilities.operatorOnly().canImport, isFalse);
    expect(const EventPipelineCapabilities.operatorOnly().canCapture, isFalse);
    expect(const EventPipelineCapabilities.booth().canCapture, isTrue);
    expect(const EventPipelineCapabilities.booth().canCaptureDevice, isTrue);
  });
}
