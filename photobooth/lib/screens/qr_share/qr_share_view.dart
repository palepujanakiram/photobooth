import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/app_settings_manager.dart';
import '../../services/whatsapp_push_coordinator.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';
import '../../utils/route_args.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/theme_background.dart';
import '../result/result_viewmodel.dart';

class QrShareScreen extends StatefulWidget {
  const QrShareScreen({super.key});

  @override
  State<QrShareScreen> createState() => _QrShareScreenState();
}

class _QrShareScreenState extends State<QrShareScreen> {
  ResultViewModel? _viewModel;
  bool _ownsViewModel = false;
  bool _initialized = false;
  Timer? _timer;
  int _secondsLeft = 60;
  bool _exiting = false;

  /// One-shot toast guard: we show the post-receipt outcome dialog at most once
  /// per QR share screen lifecycle.
  bool _postReceiptToastShown = false;

  void _onWhatsappStatusFromFcm(WhatsAppStatusPayload payload) {
    _viewModel?.applyWhatsappStatusPush(payload);
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final parsed =
        QrShareArgs.tryParse(ModalRoute.of(context)?.settings.arguments);
    if (parsed == null) return;

    final vmArg = parsed.resultViewModel;
    if (vmArg is ResultViewModel) {
      _viewModel = vmArg;
      _ownsViewModel = false;
    } else {
      _viewModel = ResultViewModel(
        generatedImages: parsed.generatedImages,
        originalPhoto: parsed.originalPhoto,
        appSettingsManager: context.read<AppSettingsManager>(),
      );
      _ownsViewModel = true;
    }
    _initialized = true;

    WhatsAppPushCoordinator.instance.registerCallback(_onWhatsappStatusFromFcm);
    _viewModel?.startWhatsappDeliveryPolling();

    // Listen for the receipt POST to settle, then surface a one-shot toast.
    // The receipt POST may have already completed by the time this screen
    // mounts (it fires from onFcmPaymentPush), so check immediately too.
    _viewModel?.addListener(_maybeShowPostReceiptToast);
    _maybeShowPostReceiptToast();

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        t.cancel();
        unawaited(_exitToStart());
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    WhatsAppPushCoordinator.instance.registerCallback(null);
    _viewModel?.removeListener(_maybeShowPostReceiptToast);
    _viewModel?.stopWhatsappDeliveryPolling();
    if (_ownsViewModel) {
      _viewModel?.dispose();
    }
    super.dispose();
  }

  /// Watches [ResultViewModel.postReceiptOutcome] and shows the spec'd toast
  /// once when the value transitions out of [PostReceiptOutcome.pending].
  void _maybeShowPostReceiptToast() {
    if (_postReceiptToastShown) return;
    final vm = _viewModel;
    if (vm == null) return;
    final outcome = vm.postReceiptOutcome;
    if (outcome == PostReceiptOutcome.pending) return;
    _postReceiptToastShown = true;

    // Defer to next frame so we never call showCupertinoDialog mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showToastFor(outcome);
    });
  }

  void _showToastFor(PostReceiptOutcome outcome) {
    switch (outcome) {
      case PostReceiptOutcome.allOk:
      case PostReceiptOutcome.whatsappSkippedOptOut:
      case PostReceiptOutcome.pending:
        // Silent: success or by-design no-WhatsApp.
        return;
      case PostReceiptOutcome.whatsappOkPdfFailed:
        AppSnackBar.showSuccess(
          context,
          'Message sent — receipt is delayed.',
        );
        return;
      case PostReceiptOutcome.whatsappSkippedInvalidPhone:
        AppSnackBar.showError(
          context,
          "That number didn't work. Scan the QR code on this screen to get your copy.",
        );
        return;
      case PostReceiptOutcome.whatsappSkippedNoPhone:
        AppSnackBar.showError(
          context,
          'No number entered. Scan the QR code on this screen to get your copy.',
        );
        return;
      case PostReceiptOutcome.receiptFailed:
        AppSnackBar.showError(
          context,
          'Could not finalize your receipt. Please show this screen to staff.',
        );
        return;
    }
  }

  Future<void> _exitToStart() async {
    if (!mounted || _exiting) return;
    _exiting = true;
    _timer?.cancel();
    try {
      await _viewModel?.privacyWipeLocal();
    } catch (e, st) {
      AppLogger.debug('Privacy wipe (qr-share) failed: $e\n$st');
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppConstants.kRouteTerms,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final parsed = QrShareArgs.tryParse(ModalRoute.of(context)?.settings.arguments);
    final shareUrl = (parsed?.shareUrl ?? '').trim();
    final kioskUrl = (parsed?.kioskShareUrl ?? '').trim();
    final qrData = shareUrl.isNotEmpty ? shareUrl : kioskUrl;
    final longUrl = (parsed?.shareLongUrl ?? '').trim();
    final expiresAt = parsed?.shareExpiresAt;

    if (!_initialized || _viewModel == null || parsed == null) {
      return Scaffold(
        backgroundColor: appColors.backgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    String expiryText() {
      if (expiresAt == null) return '';
      final local = expiresAt.toLocal();
      final hh = local.hour.toString().padLeft(2, '0');
      final mm = local.minute.toString().padLeft(2, '0');
      return 'Link expires at $hh:$mm';
    }

    return ChangeNotifierProvider.value(
      value: _viewModel!,
      child: Consumer<ResultViewModel>(
        builder: (context, viewModel, _) {
          final canShowQr = qrData.isNotEmpty;
          final expiry = expiryText();
          final phone = (parsed.customerPhone ?? '').trim();
          final waRequested = viewModel.effectiveWhatsappOptIn;
          // Server-confirmed: only true once the backend tells us the message
          // was actually queued (WhatsApp send was not skipped/rejected).
          final waActuallyQueued = viewModel.whatsappQueued;
          final vmStatus = (viewModel.whatsappDeliveryStatus ?? '').trim();
          final headline = (waActuallyQueued && phone.isNotEmpty)
              ? 'We also sent your receipt and digital copy to $phone on WhatsApp. '
                  'Anyone can still scan this QR to download a digital copy.'
              : 'Scan this QR on your phone to download a digital copy.';
          // WhatsApp status line only makes sense when the message actually
          // queued — otherwise we'd show "updating…" forever for a send that
          // will never happen. Status is rendered via friendlyWhatsappStatus
          // so customers see "Sending…" / "Delivered" / "Read", not raw enum
          // strings like "SENT" / "PENDING".
          final waLine = waActuallyQueued
              ? (vmStatus.isNotEmpty
                  ? 'WhatsApp: ${ResultViewModel.friendlyWhatsappStatus(vmStatus)}'
                  : (waRequested ? 'WhatsApp: Updating…' : ''))
              : '';
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
                onPressed: _exitToStart,
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
                            Container(
                              width: 280,
                              height: 280,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
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
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                            ),
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
                                        : () async {
                                            final messenger =
                                                ScaffoldMessenger.of(context);
                                            await viewModel.silentPrintToNetwork();
                                            if (!mounted) return;
                                            if (viewModel.hasError) {
                                              AppSnackBar.showError(
                                                messenger.context,
                                                viewModel.errorMessage ?? 'Print failed',
                                              );
                                            } else {
                                              AppSnackBar.showSuccess(
                                                messenger.context,
                                                'Print job sent!',
                                              );
                                            }
                                          },
                                    child: Text(
                                      viewModel.isPrinting ? 'Printing…' : 'Print again',
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
                                        : () async {
                                            final messenger =
                                                ScaffoldMessenger.of(context);
                                            await viewModel.shareImages();
                                            if (!mounted) return;
                                            if (viewModel.hasError) {
                                              AppSnackBar.showError(
                                                messenger.context,
                                                viewModel.errorMessage ?? 'Share failed',
                                              );
                                            }
                                          },
                                    child: Text(
                                      viewModel.isSharing ? 'Sharing…' : 'Share (kiosk)',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Resetting in ${_secondsLeft}s',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
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
        },
      ),
    );
  }
}

