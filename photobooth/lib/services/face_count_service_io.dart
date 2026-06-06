import 'dart:io';

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../utils/logger.dart';

/// On-device face count via ML Kit (Android / iOS).
Future<int> detectFaceCountFromXFile(XFile imageFile) async {
  final path = imageFile.path;
  if (path.isEmpty) return 0;

  final file = File(path);
  if (!await file.exists()) return 0;

  final detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableTracking: false,
    ),
  );

  try {
    final input = InputImage.fromFilePath(path);
    final faces = await detector.processImage(input);
    final count = faces.length;
    AppLogger.debug('FaceCountService: detected $count face(s)');
    return count;
  } catch (e, st) {
    AppLogger.error(
      'FaceCountService: detection failed (non-fatal)',
      error: e,
      stackTrace: st,
    );
    return 0;
  } finally {
    await detector.close();
  }
}
