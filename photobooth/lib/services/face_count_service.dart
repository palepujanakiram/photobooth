import 'package:camera/camera.dart';

import 'face_count_service_stub.dart'
    if (dart.library.io) 'face_count_service_io.dart' as impl;

/// Returns the number of faces detected in [imageFile] (0 if unavailable).
Future<int> detectFaceCountFromXFile(XFile imageFile) =>
    impl.detectFaceCountFromXFile(imageFile);
