import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_native_details/camera_native_details.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, compute, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show DeviceOrientation;

import '../../services/file_helper.dart';
import '../../utils/app_device_type.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';
import 'camera_description_label.dart';
import 'camera_image_yuv_jpeg.dart';
import 'photo_capture_camera_config.dart';

/// Best-effort portrait capture lock for Android built-in cameras at 0/180° sensor.
Future<void> maybeLockAndroidPortraitCapture({
  required CameraController controller,
  required CameraDescription camera,
  required int displayRotation,
}) async {
  final isExternal = isExternalCaptureCamera(camera, looksLikeExternalCameraName);
  if (isExternal ||
      kIsWeb ||
      defaultTargetPlatform != TargetPlatform.android ||
      displayRotation != 1) {
    return;
  }
  final so = camera.sensorOrientation;
  if (so != 0 && so != 180) return;
  try {
    await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
  } on CameraException {
    // Best-effort
  }
}

/// Fetches native camera details (Android Camera2; placeholder on iOS/Web).
Future<CameraDetails?> fetchNativeCameraDetails(String cameraName) async {
  try {
    return await CameraNativeDetails.getCameraDetails(cameraName);
  } catch (_) {
    return null;
  }
}

void logNativeCameraDetails(CameraDetails details) {
  AppLogger.debug('   Native camera details (${details.platform}):');
  AppLogger.debug(
    '     activeArray: ${details.activeArrayWidth}x${details.activeArrayHeight}',
  );
  AppLogger.debug(
    '     zoomRatioRange: ${details.zoomRatioRangeMin}..${details.zoomRatioRangeMax}',
  );
  AppLogger.debug('     maxDigitalZoom: ${details.maxDigitalZoom}');
  AppLogger.debug('     lensFacing: ${details.lensFacing}');
  if (details.supportedPreviewSizes.isNotEmpty) {
    final sizes = details.supportedPreviewSizes.take(5).join(', ');
    final suffix = details.supportedPreviewSizes.length > 5 ? '...' : '';
    AppLogger.debug('     previewSizes: $sizes$suffix');
  }
}

/// Waits briefly for an in-flight camera recovery before capture/fallback.
Future<void> waitForInFlightCameraRecovery(Completer<void>? recovery) async {
  if (recovery == null) return;
  try {
    await recovery.future.timeout(const Duration(seconds: 4));
  } catch (_) {}
}

/// Whether Android stream-frame fallback is allowed for this device/camera.
bool androidStreamFallbackCaptureEligible({
  required CameraDescription? camera,
  required AppDeviceType? deviceType,
}) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  if (camera == null) return false;
  final isExternal = isExternalCaptureCamera(camera, looksLikeExternalCameraName);
  return isExternal || deviceType == AppDeviceType.androidTv;
}

/// Grabs one preview stream frame and writes a JPEG [XFile].
Future<XFile> grabStreamFrameAsJpegFile({
  required CameraController controller,
  required Duration streamTimeout,
}) async {
  final completer = Completer<CameraImage>();
  var streaming = false;
  try {
    streaming = true;
    await controller.startImageStream((CameraImage image) {
      if (completer.isCompleted) return;
      completer.complete(image);
    });
    final frame = await completer.future.timeout(streamTimeout);
    await controller.stopImageStream();
    streaming = false;

    final jpegBytes = await compute(cameraImageToJpegBytes, frame);
    final tempDir = await FileHelper.getTempDirectoryPath();
    const photosSubdir = 'photos';
    final photosDir = '$tempDir/$photosSubdir';
    await FileHelper.ensureDirectory(photosDir);
    final ts = DateTime.now().millisecondsSinceEpoch;
    final savePath = '$photosDir/streamcap_$ts.jpg';
    final file = FileHelper.createFile(savePath);
    await (file as dynamic).writeAsBytes(jpegBytes);
    return XFile((file as dynamic).path);
  } finally {
    if (streaming) {
      try {
        await controller.stopImageStream();
      } catch (_) {}
    }
  }
}

/// CameraX errors that may succeed after dispose/re-init.
bool isRecoverableTakePictureError(String messageLower) {
  return messageLower.contains('recoverable') ||
      messageLower.contains('otherrecoverableerror') ||
      messageLower.contains('camera is closed') ||
      messageLower.contains('cameradeviceimpl.close') ||
      messageLower.contains('camera2') ||
      messageLower.contains('capture failed');
}

/// Whether recovery cooldown allows another attempt.
bool canAttemptCameraRecovery({
  required DateTime? lastRecoveryAt,
  required Duration cooldown,
}) {
  final last = lastRecoveryAt;
  if (last == null) return true;
  return DateTime.now().difference(last) >= cooldown;
}

Future<XFile> takePictureWithTimeout(
  CameraController controller,
  Duration timeout,
) {
  return controller.takePicture().timeout(
    timeout,
    onTimeout: () => throw TimeoutException(AppStrings.takePictureTimeout),
  );
}

/// Delay before reopening camera after dispose (Android TV CameraX).
Future<void> delayBeforeCameraReopen() {
  return Future.delayed(
    Duration(milliseconds: AppConstants.kCameraDisposeToReopenDelayMs),
  );
}
