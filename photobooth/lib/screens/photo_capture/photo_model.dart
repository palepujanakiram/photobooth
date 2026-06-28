import 'package:camera/camera.dart';

import '../../utils/json_parse_helpers.dart';

class PhotoModel {
  final String id;
  final XFile imageFile;
  final DateTime capturedAt;
  final String? cameraId;
  final bool isTransformed;

  const PhotoModel({
    required this.id,
    required this.imageFile,
    required this.capturedAt,
    this.cameraId,
    this.isTransformed = false,
  });

  PhotoModel copyWith({
    String? id,
    XFile? imageFile,
    DateTime? capturedAt,
    String? cameraId,
    bool? isTransformed,
  }) {
    return PhotoModel(
      id: id ?? this.id,
      imageFile: imageFile ?? this.imageFile,
      capturedAt: capturedAt ?? this.capturedAt,
      cameraId: cameraId ?? this.cameraId,
      isTransformed: isTransformed ?? this.isTransformed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imagePath': imageFile.path,
      'capturedAt': capturedAt.toIso8601String(),
      'cameraId': cameraId,
      'isTransformed': isTransformed,
    };
  }

  factory PhotoModel.fromJson(Map<String, dynamic> json) {
    final imagePath = JsonParseHelpers.stringValue(json['imagePath']);
    final capturedRaw = JsonParseHelpers.stringOrNull(json['capturedAt']);
    return PhotoModel(
      id: JsonParseHelpers.stringValue(json['id']),
      imageFile: XFile(imagePath),
      capturedAt: capturedRaw != null
          ? (DateTime.tryParse(capturedRaw) ?? DateTime.now())
          : DateTime.now(),
      cameraId: JsonParseHelpers.stringOrNull(json['cameraId']),
      isTransformed: JsonParseHelpers.boolOrNull(json['isTransformed']) ?? false,
    );
  }
}

