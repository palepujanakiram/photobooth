import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'result_viewmodel.dart';
import '../../services/app_settings_manager.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/centered_max_width.dart';
import '../../views/widgets/leading_with_alice.dart';
import '../../views/widgets/theme_background.dart';
import '../../views/widgets/payment_link_qr.dart';
import '../../services/payment_push_coordinator.dart';
import '../../utils/route_args.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  ResultViewModel? _viewModel;
  bool _isInitialized = false;
  bool _didNavigateToThankYou = false;
  String? _customerName;
  String? _customerPhone;
  bool _customerWhatsappOptIn = false;
  Timer? _failureIdleTimer;
  int _failureSecondsLeft = 0;
  bool _navigatingAway = false;
  bool _retryingPrint = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInitialized) return;

    final parsed = ResultArgs.tryParse(ModalRoute.of(context)?.settings.arguments);
    if (parsed == null) return;

    final generatedImages = parsed.generatedImages;
    final originalPhoto = parsed.originalPhoto;
    _customerName = parsed.customerName;
    _customerPhone = parsed.customerPhone;
    _customerWhatsappOptIn = parsed.customerWhatsappOptIn;

    if (generatedImages.isEmpty) return;

    _viewModel = ResultViewModel(
      generatedImages: generatedImages,
      originalPhoto: originalPhoto,
      appSettingsManager: context.read<AppSettingsManager>(),
      customerName: _customerName,
      customerPhone: _customerPhone,
      customerWhatsappOptIn: _customerWhatsappOptIn,
    );
    _isInitialized = true;

    PaymentPushCoordinator.instance
        .registerResultScreenCallback(_onPaymentPushFromFcm);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(PaymentPushCoordinator.instance.flushPendingStoragePayment());
      _viewModel?.loadPaymentQr(customerPhone: _customerPhone);
    });
  }

  @override
  void dispose() {
    PaymentPushCoordinator.instance.registerResultScreenCallback(null);
    _failureIdleTimer?.cancel();
    // QrShareScreen reuses the same ResultViewModel for print/share + WhatsApp status.
    if (!_didNavigateToThankYou) {
      _viewModel?.dispose();
    }
    super.dispose();
  }

  /// FCM payment push: inline status under Pay & Collect; silent print on approval.
  void _onPaymentPushFromFcm(PaymentPushPayload payload) {
    if (!mounted || _viewModel == null) return;
    // Run immediately on the main isolate (do not defer to next frame): deferred
    // delivery was dropping updates when lifecycle/FCM timing coincided with frame gaps.
    unawaited(_applyPaymentPushFromFcm(payload));
  }

  Future<void> _applyPaymentPushFromFcm(PaymentPushPayload payload) async {
    try {
      if (!mounted || _viewModel == null) return;

      await _viewModel!.onFcmPaymentPush(payload);
      if (!mounted) return;

      if (_viewModel!.fcmPaymentPushSuccess == true) {
        _failureIdleTimer?.cancel();
        _failureSecondsLeft = 0;
        if (_viewModel!.hasError) {
          AppSnackBar.showError(context, _viewModel!.errorMessage!);
        } else {
          AppSnackBar.showSuccess(context, 'Print job sent successfully!');
          await _navigateToThankYouIfEligible(_viewModel!);
        }
      } else if (_viewModel!.fcmPaymentPushSuccess == false) {
        _startFailureIdleCountdown();
      }
    } catch (e, st) {
      // Keep production UI clean: debug output is gated via AppLogger.
      AppLogger.debug('Payment FCM UI error: $e\n$st');
    }
  }

  Future<void> _confirmAndPopBack() async {
    if (!mounted || _navigatingAway) return;
    if (_viewModel?.fcmPaymentPushSuccess == true) {
      // Payment already approved; avoid leaving this screen.
      return;
    }

    final shouldExit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Cancel payment?'),
            content: const Text(
              'If you go back now, this payment will be cancelled on this screen.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Stay'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Go back'),
              ),
            ],
          ),
        ) ??
        false;

    if (!mounted) return;
    if (!shouldExit) return;
    _failureIdleTimer?.cancel();
    Navigator.of(context).maybePop();
  }

  void _startFailureIdleCountdown() {
    _failureIdleTimer?.cancel();
    if (!mounted) return;
    setState(() => _failureSecondsLeft = 60);
    _failureIdleTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_failureSecondsLeft <= 1) {
        t.cancel();
        unawaited(_navigateToStart());
        return;
      }
      setState(() => _failureSecondsLeft -= 1);
    });
  }

  Future<void> _navigateToStart() async {
    if (!mounted) return;
    if (_navigatingAway) return;
    _navigatingAway = true;
    _failureIdleTimer?.cancel();
    try {
      await _viewModel?.privacyWipeLocal();
    } catch (e, st) {
      AppLogger.debug('Privacy wipe (start) failed: $e\n$st');
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppConstants.kRouteTerms,
      (route) => false,
    );
  }

  Future<void> _navigateToThankYouIfEligible(ResultViewModel viewModel) async {
    if (!mounted || _didNavigateToThankYou) return;
    if (viewModel.fcmPaymentPushSuccess != true || viewModel.hasError) return;
    _didNavigateToThankYou = true;
    try {
      await viewModel.ensurePostPaymentShareArtifacts();
    } catch (e, st) {
      AppLogger.debug('Post-payment share preparation failed: $e\n$st');
    }
    if (!mounted) return;
    // Keep the session alive for a short window so operators can print/share.
    // QrShareScreen will wipe locally and reset back to Terms after 60s.
    Navigator.pushReplacementNamed(
      context,
      AppConstants.kRouteQrShare,
      arguments: QrShareArgs(
        generatedImages: viewModel.generatedImages,
        originalPhoto: viewModel.originalPhoto,
        resultViewModel: viewModel,
        shareUrl: viewModel.receiptShareUrl,
        shareLongUrl: viewModel.receiptShareLongUrl,
        shareExpiresAt: viewModel.receiptShareExpiresAt,
        kioskShareUrl: viewModel.kioskFallbackShareUrl,
        whatsappQueued: viewModel.whatsappQueued,
        customerWhatsappOptIn: viewModel.customerWhatsappOptIn,
        customerPhone: viewModel.customerPhone,
        receiptPdfUrl: viewModel.receiptPdfUrl,
      ),
    );
  }

  Future<void> _retryPrint(ResultViewModel viewModel) async {
    if (!mounted || _didNavigateToThankYou || _retryingPrint) return;
    if (viewModel.fcmPaymentPushSuccess != true) return;
    _retryingPrint = true;
    try {
      viewModel.clearError();
      await viewModel.silentPrintToNetwork();
      if (!mounted) return;
      if (viewModel.hasError) {
        AppSnackBar.showError(context, viewModel.errorMessage!);
        return;
      }
      AppSnackBar.showSuccess(context, 'Print job sent successfully!');
      await _navigateToThankYouIfEligible(viewModel);
    } finally {
      _retryingPrint = false;
    }
  }

  Future<void> _showGetHelpDialog(ResultViewModel viewModel) async {
    if (!mounted) return;
    // Prefer a simple operator-facing help dialog (no deep linking).
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Need help?'),
        content: const Text(
          'If your payment went through but printing didn’t start, tap Refresh.\n\n'
          'If it still doesn’t work, please contact staff at the counter.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    AppLogger.debug('Pay&Collect: help dialog shown');
  }


  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);

    if (!_isInitialized || _viewModel == null) {
      return Scaffold(
        backgroundColor: appColors.backgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return ChangeNotifierProvider.value(
      value: _viewModel!,
      child: Consumer2<ResultViewModel, AppSettingsManager>(
        builder: (context, viewModel, _, child) {
          // Approval can arrive via FCM *or* polling (session/payment status). When polling
          // drives the state, we still need to auto-advance once printing completes.
          if (!_didNavigateToThankYou &&
              viewModel.fcmPaymentPushSuccess == true &&
              !viewModel.hasError &&
              !viewModel.isPrinting) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              unawaited(_navigateToThankYouIfEligible(viewModel));
            });
          }
          return Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              forceMaterialTransparency: true,
              centerTitle: true,
              title: const Text(
                'PAY',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 22,
                ),
              ),
              bottom: const PreferredSize(
                // Give the subtitle enough height on tablets / large text scales
                // so it never collides with the title.
                preferredSize: Size.fromHeight(22),
                child: Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Scan to complete your purchase',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              leading: IconButton(
                icon: const Icon(CupertinoIcons.back, color: Colors.white),
                onPressed: _confirmAndPopBack,
              ),
              actions: const [AppBarAliceAction()],
            ),
            body: Stack(
              children: [
                const Positioned.fill(
                  child: ThemeBackground(),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    // Body is behind the app bar; account for title + subtitle height.
                    padding: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top +
                          kToolbarHeight +
                          22 +
                          6,
                    ),
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildTitleSection(appColors),
                              const SizedBox(height: 10),
                              _buildPaymentCard(context, viewModel, appColors),
                              if (viewModel.hasError) _buildErrorBanner(viewModel),
                              if (viewModel.fcmPaymentPushSuccess == true &&
                                  viewModel.hasError) ...[
                                const SizedBox(height: 14),
                                CenteredMaxWidth(
                                  maxWidth: 360,
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white,
                                        minimumSize:
                                            const Size(double.infinity, 56),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 16,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        textStyle: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      onPressed: _retryingPrint
                                          ? null
                                          : () => _retryPrint(viewModel),
                                      child: Text(
                                        _retryingPrint
                                            ? 'Retrying...'
                                            : 'Retry print',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              CenteredMaxWidth(
                                maxWidth: 360,
                                child: SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blueGrey.shade800,
                                      foregroundColor: Colors.white,
                                      minimumSize:
                                          const Size(double.infinity, 56),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 17,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onPressed: _navigateToStart,
                                    child: Text(
                                      viewModel.fcmPaymentPushSuccess == false &&
                                              _failureSecondsLeft > 0
                                          ? 'Back to start (${_failureSecondsLeft}s)'
                                          : 'Back to start',
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
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

  Widget _buildTitleSection(AppColors appColors) {
    return Padding(
      padding: const EdgeInsets.only(top: 0, bottom: 2),
      child: Text(
        'Scan the QR code to pay with UPI.\nPrinting starts automatically after payment is approved.',
        style: TextStyle(
          fontSize: 14,
          color: Colors.white.withValues(alpha: 0.8),
          height: 1.35,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildErrorBanner(ResultViewModel viewModel) {
    final message = viewModel.errorMessage ?? 'Unknown error';
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_triangle,
                color: Colors.red,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Error',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => viewModel.clearError(),
                icon:
                    const Icon(CupertinoIcons.xmark, color: Colors.red, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 160),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                message,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: message));
                if (!context.mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('Copied error details')),
                );
              },
              icon: const Icon(CupertinoIcons.doc_on_doc, size: 16),
              label: const Text('Copy'),
            ),
          ),
        ],
      ),
    );
  }

  /// Fixed height for the QR panel (kiosk-friendly).
  static const double _resultBoxHeight = 400;

  static const TextStyle _resultBoxTitleStyle = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  Widget _buildPaymentQrArea(ResultViewModel viewModel, double side) {
    final gatewayEnabled = viewModel.isPaymentGatewayEnabled;
    if (!gatewayEnabled) {
      // When payment gateway is disabled, show the static UPI QR instead of any init state/errors.
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Image.asset(
          'lib/images/upi_qr_fallback.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      );
    }
    if (viewModel.paymentInitInProgress) {
      return SizedBox(
        width: side,
        height: side,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (viewModel.paymentInitError != null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          viewModel.paymentInitError!,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
        ),
      );
    }
    final link = viewModel.paymentLink;
    if (link == null || link.isEmpty) {
      return Icon(
        CupertinoIcons.qrcode,
        size: side * 0.45,
        color: Colors.grey.shade700,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(6),
      child: PaymentLinkQr(paymentLink: link, size: side - 12),
    );
  }

  Widget _buildPaymentCard(BuildContext context, ResultViewModel viewModel, AppColors appColors) {
    final totalPrice = viewModel.totalPrice;
    return Container(
      height: _resultBoxHeight,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Keep the QR comfortably centered with even breathing room above/below.
          const headerAndFooterReserve = 160.0;
          final maxSideFromWidth =
              (constraints.maxWidth - 24).clamp(180.0, 260.0);
          final maxSideFromHeight = (constraints.maxHeight - headerAndFooterReserve)
              .clamp(160.0, 260.0);
          final side = (maxSideFromWidth < maxSideFromHeight)
              ? maxSideFromWidth
              : maxSideFromHeight;

          return Column(
            children: [
              const Text(
                'Pay via UPI',
                style: _resultBoxTitleStyle,
              ),
              const SizedBox(height: 6),
              Text(
                '₹$totalPrice',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Center(
                  child: Container(
                    width: side,
                    height: side,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    child: _buildPaymentQrArea(viewModel, side),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                viewModel.fcmPaymentPushSuccess == false
                    ? 'Payment failed. Please try again.\nYou will return to start automatically.'
                    : viewModel.fcmPaymentPushSuccess == true
                        ? 'Payment confirmed. Printing...'
                        : (viewModel.isPaymentGatewayEnabled
                            ? 'Waiting for payment confirmation...'
                            : 'Waiting for admin approval...'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: viewModel.fcmPaymentPushSuccess == false
                      ? Colors.red.shade200
                      : (viewModel.fcmPaymentPushSuccess == true
                          ? Colors.green.shade200
                          : Colors.white.withValues(alpha: 0.85)),
                ),
              ),
              if (viewModel.isDeadPollingFallbackVisible) ...[
                const SizedBox(height: 10),
                Text(
                  'Did your payment go through?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.95),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.35),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          await viewModel.refreshPaymentPolling();
                        },
                        child: const Text('Refresh'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.16),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => _showGetHelpDialog(viewModel),
                        child: const Text('Get help'),
                      ),
                    ),
                  ],
                ),
              ],
              if (viewModel.fcmPaymentPushSuccess == false &&
                  _failureSecondsLeft > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Returning to start in ${_failureSecondsLeft}s',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
