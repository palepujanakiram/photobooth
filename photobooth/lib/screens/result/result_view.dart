import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'result_viewmodel.dart';
import '../../services/app_settings_manager.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';
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
  Timer? _failureIdleTimer;
  int _failureSecondsLeft = 0;
  bool _navigatingAway = false;

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

    if (generatedImages.isEmpty) return;

    _viewModel = ResultViewModel(
      generatedImages: generatedImages,
      originalPhoto: originalPhoto,
      appSettingsManager: context.read<AppSettingsManager>(),
    );
    _isInitialized = true;

    PaymentPushCoordinator.instance
        .registerResultScreenCallback(_onPaymentPushFromFcm);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(PaymentPushCoordinator.instance.flushPendingStoragePayment());
      _viewModel?.loadPaymentQr();
    });
  }

  @override
  void dispose() {
    PaymentPushCoordinator.instance.registerResultScreenCallback(null);
    _failureIdleTimer?.cancel();
    _viewModel?.dispose();
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
      await viewModel.privacyWipeLocal();
    } catch (e, st) {
      AppLogger.debug('Privacy wipe (thankyou) failed: $e\n$st');
    }
    Navigator.pushReplacementNamed(context, AppConstants.kRouteThankYou);
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
                'Scan to Pay',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
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
                    padding: const EdgeInsets.only(top: kToolbarHeight),
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildTitleSection(appColors),
                              const SizedBox(height: 12),
                              _buildPaymentCard(context, viewModel, appColors),
                              if (viewModel.hasError) _buildErrorBanner(viewModel),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueGrey.shade800,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _navigateToStart,
                                  child: Text(
                                    viewModel.fcmPaymentPushSuccess == false &&
                                            _failureSecondsLeft > 0
                                        ? 'Back to start (${_failureSecondsLeft}s)'
                                        : 'Back to start',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Scan the QR with any UPI app.\nPrinting starts automatically after payment is approved.',
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
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_triangle,
            color: Colors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              viewModel.errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => viewModel.clearError(),
            icon: const Icon(CupertinoIcons.xmark, color: Colors.red, size: 18),
          ),
        ],
      ),
    );
  }

  /// Fixed height for the QR panel (kiosk-friendly).
  static const double _resultBoxHeight = 420;

  static const TextStyle _resultBoxTitleStyle = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  Widget _buildPaymentQrArea(ResultViewModel viewModel, double side) {
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
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final side = (constraints.maxWidth - 24).clamp(180.0, 260.0);
              return Container(
                width: side,
                height: side,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                child: _buildPaymentQrArea(viewModel, side),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            viewModel.fcmPaymentPushSuccess == false
                ? 'Payment failed. Please try again.\nYou will return to start automatically.'
                : viewModel.fcmPaymentPushSuccess == true
                    ? 'Payment confirmed. Printing...'
                    : 'Waiting for payment confirmation...',
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
          if (viewModel.fcmPaymentPushSuccess == false && _failureSecondsLeft > 0) ...[
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
      ),
      ),
    );
  }
}
