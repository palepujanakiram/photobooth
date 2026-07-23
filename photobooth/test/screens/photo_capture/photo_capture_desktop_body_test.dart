import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_desktop_body.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_viewmodel.dart';
import 'package:photobooth/screens/photo_capture/photo_model.dart';
import 'package:photobooth/utils/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PhotoCaptureDesktopBody hides when photo captured', (tester) async {
    final vm = CaptureViewModel();
    vm.capturedPhoto = PhotoModel(
      id: 'p1',
      imageFile: XFile.fromData(
        Uint8List.fromList([0xFF, 0xD8, 0xFF]),
        name: 'test.jpg',
        mimeType: 'image/jpeg',
      ),
      capturedAt: DateTime.utc(2026, 1, 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotoCaptureDesktopBody(
            viewModel: vm,
            onTakePhoto: () {},
            onPickGallery: () {},
            showGallery: true,
          ),
        ),
      ),
    );

    expect(find.text('Take Photo'), findsNothing);
  });

  testWidgets('PhotoCaptureDesktopBody shows primary actions', (tester) async {
    final vm = CaptureViewModel();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhotoCaptureDesktopBody(
            viewModel: vm,
            onTakePhoto: () {},
            onPickGallery: () {},
            showGallery: true,
            onPhoneUpload: () {},
          ),
        ),
      ),
    );

    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text(AppStrings.galleryButtonLabel), findsOneWidget);
    expect(find.text(AppStrings.phoneUploadButtonLabel), findsOneWidget);
  });
}
