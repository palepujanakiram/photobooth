import 'dart:io';

class PhotoModel {
  final String id;
  final File imageFile;
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
    File? imageFile,
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
    return PhotoModel(
      id: json['id'] as String,
      imageFile: File(json['imagePath'] as String),
      capturedAt: DateTime.parse(json['capturedAt'] as String),
      cameraId: json['cameraId'] as String?,
      isTransformed: json['isTransformed'] as bool? ?? false,
    );
  }
}

