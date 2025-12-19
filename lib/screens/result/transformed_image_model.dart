import 'dart:io';

class TransformedImageModel {
  final String id;
  final File imageFile;
  final String originalPhotoId;
  final String themeId;
  final DateTime transformedAt;

  const TransformedImageModel({
    required this.id,
    required this.imageFile,
    required this.originalPhotoId,
    required this.themeId,
    required this.transformedAt,
  });

  TransformedImageModel copyWith({
    String? id,
    File? imageFile,
    String? originalPhotoId,
    String? themeId,
    DateTime? transformedAt,
  }) {
    return TransformedImageModel(
      id: id ?? this.id,
      imageFile: imageFile ?? this.imageFile,
      originalPhotoId: originalPhotoId ?? this.originalPhotoId,
      themeId: themeId ?? this.themeId,
      transformedAt: transformedAt ?? this.transformedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imagePath': imageFile.path,
      'originalPhotoId': originalPhotoId,
      'themeId': themeId,
      'transformedAt': transformedAt.toIso8601String(),
    };
  }

  factory TransformedImageModel.fromJson(Map<String, dynamic> json) {
    return TransformedImageModel(
      id: json['id'] as String,
      imageFile: File(json['imagePath'] as String),
      originalPhotoId: json['originalPhotoId'] as String,
      themeId: json['themeId'] as String,
      transformedAt: DateTime.parse(json['transformedAt'] as String),
    );
  }
}

