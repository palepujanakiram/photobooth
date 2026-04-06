import 'package:camera/camera.dart';

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
    // Note: XFile.fromData() or similar may be needed for deserialization
    // For now, this assumes path-based reconstruction
    return PhotoModel(
      id: json['id'] as String,
      imageFile: XFile(json['imagePath'] as String),
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      cameraId: json['cameraId'] as String?,
      isTransformed: json['isTransformed'] as bool? ?? false,
    );
  }
}

