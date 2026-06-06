import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/transformation_step_display.dart';

void main() {
  test('transformationStepDisplayLabel maps known stage', () {
    expect(
      transformationStepDisplayLabel('ai_generation'),
      'AI rendered',
    );
  });

  test('transformationStepDisplayLabel falls back to raw stage', () {
    expect(
      transformationStepDisplayLabel('custom_stage'),
      'custom_stage',
    );
  });

  test('transformationStepIcon returns icon per stage', () {
    expect(
      transformationStepIcon('storage'),
      Icons.cloud_upload_outlined,
    );
  });
}
