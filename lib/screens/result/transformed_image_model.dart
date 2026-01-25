import 'package:camera/camera.dart';

class TransformedImageModel {
  final String id;
  final String imageUrl;
  final XFile? localFile;
  final String originalPhotoId;
  final String themeId;
  final DateTime transformedAt;

  const TransformedImageModel({
    required this.id,
    required this.imageUrl,
    this.localFile,
    required this.originalPhotoId,
    required this.themeId,
    required this.transformedAt,
  });

  TransformedImageModel copyWith({
    String? id,
    String? imageUrl,
    XFile? localFile,
    String? originalPhotoId,
    String? themeId,
    DateTime? transformedAt,
  }) {
    return TransformedImageModel(
      id: id ?? this.id,
      imageUrl: imageUrl ?? this.imageUrl,
      localFile: localFile ?? this.localFile,
      originalPhotoId: originalPhotoId ?? this.originalPhotoId,
      themeId: themeId ?? this.themeId,
      transformedAt: transformedAt ?? this.transformedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imageUrl': imageUrl,
      'localFilePath': localFile?.path,
      'originalPhotoId': originalPhotoId,
      'themeId': themeId,
      'transformedAt': transformedAt.toIso8601String(),
    };
  }

  factory TransformedImageModel.fromJson(Map<String, dynamic> json) {
    final localPath = json['localFilePath'] as String?;
    return TransformedImageModel(
      id: json['id'] as String,
      imageUrl: json['imageUrl'] as String,
      localFile: localPath != null ? XFile(localPath) : null,
      originalPhotoId: json['originalPhotoId'] as String,
      themeId: json['themeId'] as String,
      transformedAt: DateTime.parse(json['transformedAt'] as String),
    );
  }
}

