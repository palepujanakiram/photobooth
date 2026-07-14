import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/phone_upload_helpers.dart';
import '../../utils/app_strings.dart';
import 'photo_capture_viewmodel.dart';

/// Shows a QR for guest phone upload and waits until the ViewModel receives it.
Future<void> showPhoneUploadQrSheet({
  required BuildContext context,
  required CaptureViewModel viewModel,
}) async {
  final link = await viewModel.beginPhoneUploadQrFlow();
  if (!context.mounted) return;
  if (link == null) {
    final msg = viewModel.errorMessage ?? AppStrings.phoneUploadFailed;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg)),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF121626),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return _PhoneUploadQrSheetBody(viewModel: viewModel, link: link);
    },
  );

  if (viewModel.capturedPhoto?.cameraId != 'phone_qr') {
    viewModel.cancelPhoneUploadWait();
  }
}

class _PhoneUploadQrSheetBody extends StatelessWidget {
  const _PhoneUploadQrSheetBody({
    required this.viewModel,
    required this.link,
  });

  final CaptureViewModel viewModel;
  final PhoneUploadLinkInfo link;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final received = viewModel.capturedPhoto?.cameraId == 'phone_qr';
        if (received) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          });
        }
        final bottom = MediaQuery.paddingOf(context).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 20 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AppStrings.phoneUploadSheetTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                AppStrings.phoneUploadSheetSubtitle,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: QrImageView(
                  data: link.url,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              if (viewModel.isWaitingForPhoneUpload)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      AppStrings.phoneUploadWaiting,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              if (received)
                Text(
                  AppStrings.phoneUploadReceived,
                  style: const TextStyle(
                    color: Colors.lightGreenAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  AppStrings.phoneUploadCancelled,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
