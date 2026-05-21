import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:image/image.dart' as img;

/// Valid minimal JPEG bytes (2×2) for image helper tests.
final Uint8List kTinyJpegBytes = Uint8List.fromList(
  img.encodeJpg(img.Image(width: 2, height: 2),
      quality: 85),
);

String get kTinyJpegDataUrl => 'data:image/jpeg;base64,${base64Encode(kTinyJpegBytes)}';

XFile tinyJpegXFile({String path = '/tmp/tiny.jpg'}) => XFile.fromData(
      kTinyJpegBytes,
      name: 'tiny.jpg',
      mimeType: 'image/jpeg',
      path: path,
    );
