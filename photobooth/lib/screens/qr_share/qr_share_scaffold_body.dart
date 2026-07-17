import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../utils/app_strings.dart';
import '../../utils/route_args.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/delete_my_photos_action.dart';
import '../../views/widgets/theme_background.dart';
import '../result/result_viewmodel.dart';
import 'qr_share_print_status_widgets.dart';

/// Loaded QR share screen body (Sonar S3776 extraction from [QrShareScreen]).
class QrShareScaffoldBody extends StatelessWidget {
  const QrShareScaffoldBody({
    super.key,
    required this.viewModel,
    required this.parsed,
    required this.qrData,
    required this.longUrl,
    required this.expiry,
    required this.headline,
    required this.waLine,
    required this.secondsLeft,
    required this.onExit,
  });

  final ResultViewModel viewModel;
  final QrShareArgs parsed;
  final String qrData;
  final String longUrl;
  final String expiry;
  final String headline;
  final String waLine;
  final int secondsLeft;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final canShowQr = qrData.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        forceMaterialTransparency: true,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
          onPressed: onExit,
        ),
        title: const Text(
          'SCAN & SHARE',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: ThemeBackground()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        canShowQr ? headline : 'Preparing your share link…',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: Colors.white.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (expiry.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          expiry,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.25,
                            color: Colors.white.withValues(alpha: 0.78),
                          ),
                        ),
                      ],
                      if (waLine.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          waLine,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.25,
                            color: Colors.white.withValues(alpha: 0.78),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _QrShareCodeBox(canShowQr: canShowQr, qrData: qrData),
                      if (viewModel.shouldShowPrintProgressCard) ...[
                        const SizedBox(height: 16),
                        QrSharePrintStatusCard(progress: viewModel.printProgress),
                      ],
                      if (longUrl.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SelectableText(
                          longUrl,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.25,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _QrShareActionRow(
                        viewModel: viewModel,
                        secondsLeft: secondsLeft,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrShareCodeBox extends StatelessWidget {
  const _QrShareCodeBox({required this.canShowQr, required this.qrData});

  final bool canShowQr;
  final String qrData;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: canShowQr
          ? QrImageView(
              data: qrData,
              backgroundColor: Colors.white,
              errorStateBuilder: (ctx, err) => Center(
                child: Text(
                  err.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            )
          : const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
    );
  }
}

class _QrShareActionRow extends StatelessWidget {
  const _QrShareActionRow({
    required this.viewModel,
    required this.secondsLeft,
  });

  final ResultViewModel viewModel;
  final int secondsLeft;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey.shade800,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: viewModel.isPrinting
                    ? null
                    : () => _onPrintAgain(context, viewModel),
                child: Text(
                  viewModel.isSilentPrinting || viewModel.isDialogPrinting
                      ? 'Printing…'
                      : 'Print again',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: viewModel.isSharing
                    ? null
                    : () => _onShareKiosk(context, viewModel),
                child: Text(
                  viewModel.isSharing ? 'Sharing…' : 'Share (kiosk)',
                ),
              ),
            ),
          ],
        ),
        if (viewModel.isReceiptPrinterConfigured) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: viewModel.isPrintingReceipt
                  ? null
                  : () => _onPrintReceipt(context, viewModel),
              child: Text(
                viewModel.isPrintingReceipt
                    ? AppStrings.printingReceiptButton
                    : AppStrings.printReceiptButton,
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Resetting in ${secondsLeft}s',
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        const DeleteMyPhotosButton(compact: true),
      ],
    );
  }

  Future<void> _onPrintReceipt(
    BuildContext context,
    ResultViewModel viewModel,
  ) async {
    final ok = await viewModel.printReceiptToNetwork(showErrors: true);
    if (!context.mounted) return;
    if (ok) {
      AppSnackBar.showSuccess(context, AppStrings.receiptPrintSuccess);
      return;
    }
    if (viewModel.hasError) {
      AppSnackBar.showError(
        context,
        viewModel.errorMessage ?? AppStrings.receiptPrintFailedGeneric,
      );
    }
  }

  Future<void> _onPrintAgain(
    BuildContext context,
    ResultViewModel viewModel,
  ) async {
    await viewModel.silentPrintToNetwork();
    if (!context.mounted) return;
    if (viewModel.hasError) {
      AppSnackBar.showError(
        context,
        viewModel.errorMessage ?? 'Print failed',
      );
    }
  }

  Future<void> _onShareKiosk(
    BuildContext context,
    ResultViewModel viewModel,
  ) async {
    await viewModel.shareImages();
    if (!context.mounted) return;
    if (viewModel.hasError) {
      AppSnackBar.showError(
        context,
        viewModel.errorMessage ?? 'Share failed',
      );
    }
  }
}
