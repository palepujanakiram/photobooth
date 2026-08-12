import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth/services/dnp/dnp_print_image_prepare.dart';
import 'package:photobooth/utils/constants.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveStaffDnpPrintSize', () {
    test('keeps strip dual size regardless of portrait dimensions', () {
      expect(
        resolveStaffDnpPrintSize(
          imageUrl: 'https://cdn/strip.jpg',
          stripCompositeUrl: 'https://cdn/strip.jpg',
          orientedDimensions: (width: 900, height: 1800),
        ),
        AppConstants.kPrintSizeStripDual2x6,
      );
    });

    test('uses portrait 4x6 for upright AI aspect when session token is ambiguous', () {
      expect(
        resolveStaffDnpPrintSize(
          imageUrl: 'https://cdn/ai.jpg',
          sessionPrintSize: AppConstants.kPrintSizeLandscape6x4,
          orientedDimensions: (width: 1200, height: 1800),
        ),
        AppConstants.kPrintSizePortrait4x6,
      );
    });

    test('uses landscape 6x4 for wide aspect', () {
      expect(
        resolveStaffDnpPrintSize(
          imageUrl: 'https://cdn/wide.jpg',
          orientedDimensions: (width: 1800, height: 1200),
        ),
        AppConstants.kPrintSizeLandscape6x4,
      );
    });

    test('falls back to session token when dimensions unknown', () {
      expect(
        resolveStaffDnpPrintSize(
          imageUrl: 'https://cdn/ai.jpg',
          sessionPrintSize: AppConstants.kPrintSizePortrait4x6,
        ),
        AppConstants.kPrintSizePortrait4x6,
      );
    });

    test('falls back when oriented dimensions are non-positive', () {
      expect(
        resolveStaffDnpPrintSize(
          imageUrl: 'https://cdn/ai.jpg',
          sessionPrintSize: AppConstants.kPrintSizeLandscape6x4,
          orientedDimensions: (width: 0, height: 100),
        ),
        AppConstants.kPrintSizeLandscape6x4,
      );
    });
  });

  group('letterboxImageToAspect', () {
    test('pads square into 4×6 without cropping width', () {
      final square = img.Image(width: 100, height: 100);
      img.fill(square, color: img.ColorRgb8(200, 100, 50));
      final out = letterboxImageToAspect(square, 4 / 6);
      expect(out, isNotNull);
      expect(out!.width, 100);
      expect(out.height, closeTo(150, 1));
      // Top letterbox is black; mid content stays orange.
      expect(out.getPixel(50, 0).r, lessThan(20));
      expect(out.getPixel(50, out.height ~/ 2).r, greaterThan(150));
    });

    test('pads tall portrait into landscape 6×4 by widening canvas', () {
      final tall = img.Image(width: 100, height: 200);
      img.fill(tall, color: img.ColorRgb8(200, 100, 50));
      final out = letterboxImageToAspect(tall, 6 / 4);
      expect(out, isNotNull);
      expect(out!.height, 200);
      expect(out.width, closeTo(300, 1));
      expect(out.getPixel(0, 100).r, lessThan(20));
      expect(out.getPixel(out.width ~/ 2, 100).r, greaterThan(150));
    });

    test('no-ops when aspect already matches', () {
      final portrait = img.Image(width: 100, height: 150);
      expect(letterboxImageToAspect(portrait, 4 / 6), isNull);
    });

    test('returns null for non-positive target aspect', () {
      final square = img.Image(width: 10, height: 10);
      expect(letterboxImageToAspect(square, 0), isNull);
      expect(letterboxImageToAspect(square, -1), isNull);
    });

    test('networkPrintSizeAspectRatio maps paper tokens only', () {
      expect(
        networkPrintSizeAspectRatio(AppConstants.kPrintSizePortrait4x6),
        closeTo(4 / 6, 1e-9),
      );
      expect(
        networkPrintSizeAspectRatio(AppConstants.kPrintSizeLandscape6x4),
        closeTo(6 / 4, 1e-9),
      );
      expect(
        networkPrintSizeAspectRatio(AppConstants.kPrintSizeStripDual2x6),
        isNull,
      );
    });
  });

  group('orientedDimensionsFromBytes', () {
    test('returns null for invalid bytes', () {
      expect(orientedDimensionsFromBytes(Uint8List.fromList([0, 1, 2])), isNull);
    });

    test('returns baked dimensions for valid JPEG bytes', () {
      final image = img.Image(width: 120, height: 80);
      final bytes = Uint8List.fromList(img.encodeJpg(image));
      expect(
        orientedDimensionsFromBytes(bytes),
        (width: 120, height: 80),
      );
    });
  });

  group('normalizeExifOrientationForDnpPrint', () {
    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
        if (call.method == 'getTemporaryDirectory') {
          return Directory.systemTemp.path;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
    });

    test('returns same file when bytes are empty', () async {
      final dir = await Directory.systemTemp.createTemp('dnp_print_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/empty.jpg');
      await file.writeAsBytes([]);
      final input = XFile(file.path);
      final output = await normalizeExifOrientationForDnpPrint(input);
      expect(output.path, input.path);
    });

    test('writeNormalizedDnpPrintFile writes temp JPEG', () async {
      final output = await writeNormalizedDnpPrintFile(
        img.Image(width: 120, height: 180),
      );
      expect(output.path, isNotEmpty);
      expect(await File(output.path).exists(), isTrue);
    });

    test('returns same file for valid JPEG without EXIF rotation', () async {
      final dir = await Directory.systemTemp.createTemp('dnp_print_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/plain.jpg');
      await file.writeAsBytes(img.encodeJpg(img.Image(width: 120, height: 80)));
      final output = await normalizeExifOrientationForDnpPrint(XFile(file.path));
      expect(output.path, file.path);
    });

    test('returns same file when jpeg decode fails', () async {
      final dir = await Directory.systemTemp.createTemp('dnp_print_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/invalid.jpg');
      await file.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
      final input = XFile(file.path);
      final output = await normalizeExifOrientationForDnpPrint(input);
      expect(output.path, input.path);
    });

    test('finalizeNormalizedDnpPrint writes when baked size differs', () async {
      final dir = await Directory.systemTemp.createTemp('dnp_print_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/source.jpg');
      await file.writeAsBytes(img.encodeJpg(img.Image(width: 200, height: 100)));
      final decoded = img.Image(width: 200, height: 100);
      final baked = img.Image(width: 100, height: 200);
      final output = await finalizeNormalizedDnpPrint(
        XFile(file.path),
        decoded,
        baked,
      );
      expect(output.path, isNot(file.path));
    });

    test('finalizeNormalizedDnpPrint returns original when unchanged', () async {
      final dir = await Directory.systemTemp.createTemp('dnp_print_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/source.jpg');
      await file.writeAsBytes(img.encodeJpg(img.Image(width: 100, height: 100)));
      final image = img.Image(width: 100, height: 100);
      final output = await finalizeNormalizedDnpPrint(
        XFile(file.path),
        image,
        image,
      );
      expect(output.path, file.path);
    });
  });

  group('letterboxImageToNetworkPrintSize / prepareImageForDnpPrint', () {
    const pathProviderChannel =
        MethodChannel('plugins.flutter.io/path_provider');

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, (call) async {
        if (call.method == 'getTemporaryDirectory') {
          return Directory.systemTemp.path;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProviderChannel, null);
    });

    Future<XFile> _jpegFile(img.Image image, {String name = 'src.jpg'}) async {
      final dir = await Directory.systemTemp.createTemp('dnp_letterbox');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/$name');
      await file.writeAsBytes(img.encodeJpg(image));
      return XFile(file.path);
    }

    test('no-ops for strip / unknown network print sizes', () async {
      final input = await _jpegFile(img.Image(width: 100, height: 100));
      final out = await letterboxImageToNetworkPrintSize(
        input,
        AppConstants.kPrintSizeStripDual2x6,
      );
      expect(out.path, input.path);
    });

    test('returns same file when bytes are empty', () async {
      final dir = await Directory.systemTemp.createTemp('dnp_letterbox');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/empty.jpg');
      await file.writeAsBytes([]);
      final input = XFile(file.path);
      final out = await letterboxImageToNetworkPrintSize(
        input,
        AppConstants.kPrintSizePortrait4x6,
      );
      expect(out.path, input.path);
    });

    test('returns same file when decode fails', () async {
      final dir = await Directory.systemTemp.createTemp('dnp_letterbox');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/invalid.jpg');
      await file.writeAsBytes([0xFF, 0xD8, 0xFF, 0xD9]);
      final input = XFile(file.path);
      final out = await letterboxImageToNetworkPrintSize(
        input,
        AppConstants.kPrintSizePortrait4x6,
      );
      expect(out.path, input.path);
    });

    test('returns same file when aspect already matches paper', () async {
      final input = await _jpegFile(img.Image(width: 100, height: 150));
      final out = await letterboxImageToNetworkPrintSize(
        input,
        AppConstants.kPrintSizePortrait4x6,
      );
      expect(out.path, input.path);
    });

    test('writes letterboxed JPEG when aspect mismatches paper', () async {
      final input = await _jpegFile(img.Image(width: 100, height: 100));
      final out = await letterboxImageToNetworkPrintSize(
        input,
        AppConstants.kPrintSizePortrait4x6,
      );
      expect(out.path, isNot(input.path));
      expect(await File(out.path).exists(), isTrue);
      final decoded = img.decodeImage(await File(out.path).readAsBytes());
      expect(decoded, isNotNull);
      expect(decoded!.width, 100);
      expect(decoded.height, closeTo(150, 1));
    });

    test('prepareImageForDnpPrint EXIF-bakes then letterboxes', () async {
      final input = await _jpegFile(img.Image(width: 120, height: 80));
      final out = await prepareImageForDnpPrint(
        input,
        networkPrintSize: AppConstants.kPrintSizePortrait4x6,
      );
      expect(out.path, isNotEmpty);
      expect(await File(out.path).exists(), isTrue);
      final decoded = img.decodeImage(await File(out.path).readAsBytes());
      expect(decoded, isNotNull);
      expect(decoded!.width / decoded.height, closeTo(4 / 6, 0.05));
    });
  });
}
