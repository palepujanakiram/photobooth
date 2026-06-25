import 'dart:io';

import 'package:camera/camera.dart';
import 'package:face_count/face_count.dart';

import '../utils/logger.dart';

/// On-device face count via ML Kit (Android) or Apple Vision (iOS).
Future<int> detectFaceCountFromXFile(XFile imageFile) async {
  if (!Platform.isAndroid && !Platform.isIOS) return 0;

  final path = imageFile.path;
  if (path.isEmpty) return 0;

  final file = File(path);
  if (!await file.exists()) return 0;

  try {
    final count = await FaceCount.detectFaceCount(path);
    AppLogger.debug('FaceCountService: detected $count face(s)');
    return count;
  } catch (e, st) {
    AppLogger.error(
      'FaceCountService: detection failed (non-fatal)',
      error: e,
      stackTrace: st,
    );
    return 0;
  }
}
