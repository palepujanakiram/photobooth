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

  handlePhoneUploadSheetClosed(viewModel);
}

/// Cancels the phone-upload wait when the sheet closes without a QR capture.
@visibleForTesting
void handlePhoneUploadSheetClosed(CaptureViewModel viewModel) {
  if (viewModel.capturedPhoto?.cameraId != 'phone_qr') {
    viewModel.cancelPhoneUploadWait();
  }
}

class _PhoneUploadQrSheetBody extends StatefulWidget {
  const _PhoneUploadQrSheetBody({
    required this.viewModel,
    required this.link,
  });

  final CaptureViewModel viewModel;
  final PhoneUploadLinkInfo link;

  @override
  State<_PhoneUploadQrSheetBody> createState() =>
      _PhoneUploadQrSheetBodyState();
}

class _PhoneUploadQrSheetBodyState extends State<_PhoneUploadQrSheetBody> {
  /// Guards against multiple [Navigator.pop]s when the ViewModel notifies
  /// more than once after a successful upload (would otherwise pop Capture
  /// and reveal the slideshow under the stack).
  bool _autoCloseScheduled = false;

  CaptureViewModel get _viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel.addListener(_onViewModelChanged);
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    super.dispose();
  }

  void _onViewModelChanged() {
    if (_autoCloseScheduled) return;
    if (_viewModel.capturedPhoto?.cameraId != 'phone_qr') return;
    _autoCloseScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        final received = _viewModel.capturedPhoto?.cameraId == 'phone_qr';
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
              const Text(
                AppStrings.phoneUploadSheetTitle,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                AppStrings.phoneUploadSheetSubtitle,
                style: TextStyle(
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
                  data: widget.link.url,
                  size: 220,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              if (_viewModel.isWaitingForPhoneUpload)
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      AppStrings.phoneUploadWaiting,
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              if (received)
                const Text(
                  AppStrings.phoneUploadReceived,
                  style: TextStyle(
                    color: Colors.lightGreenAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  AppStrings.phoneUploadCancelled,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
