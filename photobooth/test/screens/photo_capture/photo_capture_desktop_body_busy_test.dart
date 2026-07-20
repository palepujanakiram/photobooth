import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_desktop_body.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_viewmodel.dart';
import 'package:photobooth/screens/photo_capture/photo_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('PhotoCaptureDesktopBody busy states show spinners', (tester) async {
    final vm = CaptureViewModel();
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: vm,
          builder: (context, _) {
            return PhotoCaptureDesktopBody(
              viewModel: vm,
              onTakePhoto: () {},
              onPickGallery: () {},
              showGallery: true,
              onPhoneUpload: () {},
            );
          },
        ),
      ),
    );

    vm.setCaptureUiStateForTest(isCapturing: true);
    await tester.pump();
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

    vm.setCaptureUiStateForTest(
      isCapturing: false,
      isSelectingFromGallery: true,
    );
    await tester.pump();
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

    vm.setCaptureUiStateForTest(
      isSelectingFromGallery: false,
      isWaitingForPhoneUpload: true,
    );
    await tester.pump();
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
  });
}
