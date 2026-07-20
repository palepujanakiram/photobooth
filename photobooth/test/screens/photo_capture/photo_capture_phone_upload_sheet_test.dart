import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_phone_upload_sheet.dart';
import 'package:photobooth/screens/photo_capture/photo_capture_viewmodel.dart';
import 'package:photobooth/screens/photo_capture/photo_model.dart';
import 'package:photobooth/services/phone_upload_helpers.dart';
import 'package:photobooth/utils/app_strings.dart';

void main() {
  testWidgets('showPhoneUploadQrSheet shows snackbar when link missing', (tester) async {
    final vm = _PhoneUploadTestViewModel(link: null, error: 'upload failed');

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () => showPhoneUploadQrSheet(
                  context: context,
                  viewModel: vm,
                ),
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('upload failed'), findsOneWidget);
  });

  testWidgets('showPhoneUploadQrSheet auto-closes when phone photo arrives', (tester) async {
    final vm = _PhoneUploadTestViewModel(
      link: const PhoneUploadLinkInfo(
        token: 'abc',
        url: 'https://example.com/u/abc',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  await showPhoneUploadQrSheet(
                    context: context,
                    viewModel: vm,
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    expect(find.text(AppStrings.phoneUploadSheetTitle), findsOneWidget);

    vm.capturedPhoto = PhotoModel(
      id: 'phone',
      imageFile: XFile.fromData(
        Uint8List.fromList([0xFF, 0xD8, 0xFF]),
        name: 'phone.jpg',
        mimeType: 'image/jpeg',
      ),
      capturedAt: DateTime.utc(2026, 1, 1),
      cameraId: 'phone_qr',
    );
    vm.setCaptureUiStateForTest(isWaitingForPhoneUpload: false);
    await tester.pump();
    await tester.pump();

    expect(find.text(AppStrings.phoneUploadSheetTitle), findsNothing);
  });

  testWidgets('showPhoneUploadQrSheet cancel button closes sheet', (tester) async {
    final vm = _PhoneUploadTestViewModel(
      link: const PhoneUploadLinkInfo(
        token: 'abc',
        url: 'https://example.com/u/abc',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  await showPhoneUploadQrSheet(
                    context: context,
                    viewModel: vm,
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    expect(find.text(AppStrings.phoneUploadSheetTitle), findsOneWidget);

    final cancelButton = tester.widget<TextButton>(find.byType(TextButton));
    cancelButton.onPressed?.call();
    await tester.pump();
    expect(find.text(AppStrings.phoneUploadSheetTitle), findsNothing);
    expect(vm.isWaitingForPhoneUpload, isFalse);
  });

  test('handlePhoneUploadSheetClosed cancels wait without phone capture', () {
    final vm = CaptureViewModel();
    vm.setCaptureUiStateForTest(isWaitingForPhoneUpload: true);
    handlePhoneUploadSheetClosed(vm);
    expect(vm.isWaitingForPhoneUpload, isFalse);
  });

  testWidgets('cancelPhoneUploadSheet pops the current route', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () {
                navigatorKey.currentState!.push(
                  MaterialPageRoute<void>(
                    builder: (routeContext) => Scaffold(
                      body: TextButton(
                        onPressed: () => cancelPhoneUploadSheet(routeContext),
                        child: const Text('cancel'),
                      ),
                    ),
                  ),
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('cancel'), findsOneWidget);

    await tester.tap(find.text('cancel'));
    await tester.pumpAndSettle();
    expect(find.text('cancel'), findsNothing);
  });
}

class _PhoneUploadTestViewModel extends CaptureViewModel {
  _PhoneUploadTestViewModel({required this.link, this.error});

  final PhoneUploadLinkInfo? link;
  final String? error;

  @override
  Future<PhoneUploadLinkInfo?> beginPhoneUploadQrFlow() async {
    if (error != null) {
      setCaptureUiStateForTest(errorMessage: error);
      return null;
    }
    setCaptureUiStateForTest(isWaitingForPhoneUpload: true);
    return link;
  }
}
