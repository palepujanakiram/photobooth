import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'result_payment_card_widgets.dart';
import 'result_payment_qr_area.dart';
import 'result_payment_status.dart';
import 'result_viewmodel.dart';
import '../../services/app_settings_manager.dart';
import '../../utils/constants.dart';
import '../../utils/app_strings.dart';
import '../../utils/logger.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/centered_max_width.dart';
import '../../views/widgets/leading_with_alice.dart';
import '../../views/widgets/theme_background.dart';
import '../../views/widgets/delete_my_photos_action.dart';
import '../../services/payment_push_coordinator.dart';
import '../../services/kiosk_manager.dart';
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
  String? _customerPhone;
  bool? _paymentsEnabledOverride;
  Timer? _failureIdleTimer;
  int _failureSecondsLeft = 0;
  bool _navigatingAway = false;
  bool _retryingPrint = false;

  /// True while the dead-polling [Refresh] CTA's one-shot fetch is in flight.
  /// Prevents double-taps on slow connections and lets us swap the button
  /// label for an inline spinner.
  bool _refreshingPolling = false;

  /// Guards [WidgetsBinding.addPostFrameCallback] so we do not queue duplicate
  /// thank-you navigations on every [Consumer] rebuild (same as pre-refactor intent).
  bool _thankYouNavigationScheduled = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInitialized) return;

    final parsed =
        ResultArgs.tryParse(ModalRoute.of(context)?.settings.arguments);
    if (parsed == null) return;

    final generatedImages = parsed.generatedImages;
    final originalPhoto = parsed.originalPhoto;
    _customerPhone = parsed.customerPhone;

    if (generatedImages.isEmpty) return;

    _viewModel = ResultViewModel(
      generatedImages: generatedImages,
      originalPhoto: originalPhoto,
      printOrientation: parsed.printOrientation,
      appSettingsManager: context.read<AppSettingsManager>(),
      contact: parsed.contact,
    );
    _viewModel!.refreshPrinterFromSettings();
    _isInitialized = true;
    unawaited(_initPaymentMode());
  }

  Future<void> _initPaymentMode() async {
    final v = await KioskManager().getPaymentEnabledOverride();
    if (!mounted) return;
    setState(() => _paymentsEnabledOverride = v);
    final paymentsEnabled = _paymentsEnabledOverride ?? true;
    if (!paymentsEnabled) {
      PaymentPushCoordinator.instance.registerResultScreenCallback(null);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_triggerFreeModePrint());
      });
      return;
    }

    PaymentPushCoordinator.instance
        .registerResultScreenCallback(_onPaymentPushFromFcm);

    final checkoutAmount = _viewModel!.checkoutAmount;
    if (checkoutAmount <= 0 && _viewModel!.collectPaymentBeforeGeneration) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_triggerFreeModePrint());
      });
      return;
    }

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

  Future<void> _triggerFreeModePrint() async {
    if (!mounted || _viewModel == null) return;
    await _viewModel!.onFreeCheckoutPrint();
    if (!mounted || _viewModel == null) return;
    await _navigateToThankYouIfEligible(_viewModel!);
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

      await _onPaymentPushOutcome(_viewModel!);
    } catch (e, st) {
      AppLogger.debug('Payment FCM UI error: $e\n$st');
    }
  }

  Future<void> _onPaymentPushOutcome(ResultViewModel viewModel) async {
    if (viewModel.fcmPaymentPushSuccess == true) {
      _failureIdleTimer?.cancel();
      _failureSecondsLeft = 0;
      if (!kIsWeb || !viewModel.hasError) {
        AppSnackBar.showSuccess(
          context,
          AppStrings.paymentConfirmedTitle,
        );
      }
      await _navigateToThankYouIfEligible(viewModel);
      return;
    }
    if (viewModel.fcmPaymentPushSuccess == false) {
      _startFailureIdleCountdown();
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
    if (viewModel.fcmPaymentPushSuccess != true) return;
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
      AppSnackBar.showSuccess(context, AppStrings.printJobSentSuccess);
      await _navigateToThankYouIfEligible(viewModel);
    } finally {
      _retryingPrint = false;
    }
  }

  Widget _buildRefreshPollingChild() {
    if (_refreshingPolling) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }
    return const Text('Refresh');
  }

  String _backToStartLabel(ResultViewModel viewModel) {
    if (viewModel.fcmPaymentPushSuccess == false && _failureSecondsLeft > 0) {
      return 'Back to start (${_failureSecondsLeft}s)';
    }
    return 'Back to start';
  }

  /// When payment succeeds via FCM or polling, auto-advance once printing finishes.
  /// Called from [build]; must not enqueue multiple callbacks per frame storm.
  void _scheduleThankYouNavigationIfNeeded(ResultViewModel viewModel) {
    if (viewModel.fcmPaymentPushSuccess != true) {
      _thankYouNavigationScheduled = false;
      return;
    }
    if (_didNavigateToThankYou || _thankYouNavigationScheduled) return;
    _thankYouNavigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _thankYouNavigationScheduled = false;
      if (!mounted || _didNavigateToThankYou) return;
      unawaited(_navigateToThankYouIfEligible(viewModel));
    });
  }

  Widget _buildPayScreenBody(
    BuildContext context,
    ResultViewModel viewModel,
    AppColors appColors,
    bool paymentsEnabled,
  ) {
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
          const Positioned.fill(child: ThemeBackground()),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top +
                    kToolbarHeight +
                    22 +
                    6,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTitleSection(appColors),
                            const SizedBox(height: 8),
                            if (paymentsEnabled)
                              Expanded(
                                child: _buildPaymentCard(
                                  context,
                                  viewModel,
                                  appColors,
                                ),
                              )
                            else
                              const Spacer(),
                            if (viewModel.hasError)
                              _buildErrorBanner(viewModel),
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
                                      minimumSize: const Size(
                                        double.infinity,
                                        56,
                                      ),
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
                            const SizedBox(height: 12),
                            CenteredMaxWidth(
                              maxWidth: 360,
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueGrey.shade800,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(
                                      double.infinity,
                                      52,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
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
                                  child: Text(_backToStartLabel(viewModel)),
                                ),
                              ),
                            ),
                            if (viewModel.fcmPaymentPushSuccess != true)
                              CenteredMaxWidth(
                                maxWidth: 360,
                                child: DeleteMyPhotosButton(
                                  onBeforeDelete: () async {
                                    _viewModel?.stopPaymentPolling();
                                  },
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
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
    final paymentsEnabled = _paymentsEnabledOverride ?? true;

    if (!_isInitialized || _viewModel == null) {
      return Scaffold(
        backgroundColor: appColors.backgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return ChangeNotifierProvider.value(
      value: _viewModel!,
      child: Consumer2<ResultViewModel, AppSettingsManager>(
        builder: (context, viewModel, settingsManager, child) {
          _scheduleThankYouNavigationIfNeeded(viewModel);
          return _buildPayScreenBody(
            context,
            viewModel,
            appColors,
            paymentsEnabled,
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
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
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
                icon: const Icon(CupertinoIcons.xmark,
                    color: Colors.red, size: 18),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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

  Widget _buildPaymentQrArea(ResultViewModel viewModel, double maxQrWidth) {
    return ResultPaymentQrArea(
      viewModel: viewModel,
      maxQrWidth: maxQrWidth,
      onRetry: () => viewModel.retryLoadPaymentQr(
        customerPhone: _customerPhone,
      ),
    );
  }

  Widget _buildPaymentCard(
      BuildContext context, ResultViewModel viewModel, AppColors appColors) {
    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final cardHeight = computePaymentCardHeight(outerConstraints);
        return Container(
          height: cardHeight,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
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
              final maxQrWidth =
                  (constraints.maxWidth - 12).clamp(240.0, 460.0).toDouble();

              return ResultPaymentCardColumn(
                viewModel: viewModel,
                maxQrWidth: maxQrWidth,
                refreshingPolling: _refreshingPolling,
                failureSecondsLeft: _failureSecondsLeft,
                onRefreshPolling: () async {
                  if (!mounted) return;
                  setState(() => _refreshingPolling = true);
                  try {
                    await viewModel.refreshPaymentPolling();
                  } finally {
                    if (mounted) {
                      setState(() => _refreshingPolling = false);
                    }
                  }
                },
                onGetHelp: () => _showGetHelpDialog(viewModel),
                refreshPollingChild: _buildRefreshPollingChild(),
                buildQrArea: _buildPaymentQrArea,
              );
            },
          ),
        );
      },
    );
  }
}
