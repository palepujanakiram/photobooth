import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/classic_pose_countdown.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  test('defaults null to 10', () {
    expect(
      normalizeClassicPoseCountdownSeconds(null),
      AppConstants.kFlashbackCaptureCountdownSeconds,
    );
  });

  test('clamps below min and above max', () {
    expect(
      normalizeClassicPoseCountdownSeconds(4),
      AppConstants.kClassicPoseCountdownMinSeconds,
    );
    expect(
      normalizeClassicPoseCountdownSeconds(16),
      AppConstants.kClassicPoseCountdownMaxSeconds,
    );
  });

  test('keeps in-range values', () {
    expect(normalizeClassicPoseCountdownSeconds(5), 5);
    expect(normalizeClassicPoseCountdownSeconds(7), 7);
    expect(normalizeClassicPoseCountdownSeconds(15), 15);
  });
}
