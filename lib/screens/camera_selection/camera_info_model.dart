import 'package:camera/camera.dart';

class CameraInfoModel {
  final CameraDescription camera;
  final String name;
  final bool isFrontFacing;

  const CameraInfoModel({
    required this.camera,
    required this.name,
    required this.isFrontFacing,
  });

  CameraInfoModel copyWith({
    CameraDescription? camera,
    String? name,
    bool? isFrontFacing,
  }) {
    return CameraInfoModel(
      camera: camera ?? this.camera,
      name: name ?? this.name,
      isFrontFacing: isFrontFacing ?? this.isFrontFacing,
    );
  }
}

