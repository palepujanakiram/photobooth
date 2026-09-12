import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/event_pipeline_capabilities.dart';

void main() {
  test('web is an operator console', () {
    final caps = EventPipelineCapabilities.ofPlatform(isWeb: true);
    expect(caps.hasLocalLedger, isFalse);
    expect(caps.canImport, isFalse);
    expect(caps.canCapture, isFalse);
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
    expect(caps.canPrintUsb, isTrue);
  });

  test('iOS can hold a replica but not USB hardware', () {
    final caps = EventPipelineCapabilities.ofPlatform(
      isWeb: false,
      platform: TargetPlatform.iOS,
    );
    expect(caps.hasLocalLedger, isTrue);
    expect(caps.canImport, isFalse);
    expect(caps.canCapture, isFalse);
  });

  test('named constructors match the two roles', () {
    expect(const EventPipelineCapabilities.operatorOnly().canImport, isFalse);
    expect(const EventPipelineCapabilities.booth().canCapture, isTrue);
  });
}
