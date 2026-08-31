import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings_manager.dart';
import '../../services/payment_push_coordinator.dart';
import '../../services/session_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/fotoflashback_payment_helpers.dart';
import '../../utils/payment_workflow_helpers.dart';
import '../../utils/route_args.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/centered_max_width.dart';
import '../../views/widgets/kiosk_payment_qr_display.dart';
import '../../views/widgets/theme_background.dart';
import '../result/result_payment_coupon_row.dart';
import '../theme_selection/theme_model.dart';
import 'pre_payment_viewmodel.dart';

class PrePaymentScreen extends StatefulWidget {
  const PrePaymentScreen({super.key});

  @override
  State<PrePaymentScreen> createState() => _PrePaymentScreenState();
}

class _PrePaymentScreenState extends State<PrePaymentScreen> {
  PrePaymentViewModel? _viewModel;
  GenerateArgs? _generateArgs;
  FlashbackPrePayArgs? _flashbackArgs;
  bool _refreshingPolling = false;
  bool _composingFlashback = false;

  ThemeModel? get _theme =>
      _generateArgs?.theme ?? _flashbackArgs?.theme;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    _generateArgs = GenerateArgs.tryParse(raw);
    _flashbackArgs = FlashbackPrePayArgs.tryParse(raw);
    if (_generateArgs == null && _flashbackArgs == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).maybePop();
      });
      return;
    }
    _viewModel = PrePaymentViewModel(
      appSettingsManager: context.read<AppSettingsManager>(),
    )..onApproved = _onPaymentApproved;
    unawaited(_bootstrapPayment());
  }

  Future<void> _bootstrapPayment() async {
    if (SessionManager().isOfflineSession) {
      _onPaymentApproved();
      return;
    }
    final paymentsEnabled = await resolvePaymentsEnabled();
    if (!mounted) return;
    if (!paymentsEnabled) {
      _onPaymentApproved();
      return;
    }
    PaymentPushCoordinator.instance
        .registerResultScreenCallback(_onPaymentPushFromFcm);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(PaymentPushCoordinator.instance.flushPendingStoragePayment());
      _viewModel?.loadPaymentQr(photoForSessionSync: _generateArgs?.photo);
    });
  }

  void _onPaymentPushFromFcm(PaymentPushPayload payload) {
    unawaited(_viewModel?.onFcmPaymentPush(payload));
  }

  void _onPaymentApproved() {
    if (!mounted) return;
    final flashback = _flashbackArgs;
    if (flashback != null) {
      unawaited(_finishFlashback(flashback));
      return;
    }
    final args = _generateArgs;
    if (args == null) return;
    Navigator.pushReplacementNamed(
      context,
      AppConstants.kRouteGenerateProgress,
      arguments: args,
    );
  }

  Future<void> _finishFlashback(FlashbackPrePayArgs args) async {
    if (_composingFlashback) return;
    setState(() => _composingFlashback = true);
    try {
      final error = await composeFlashbackAfterPrePay(
        context: context,
        args: args,
      );
      if (!mounted) return;
      if (error != null) {
        AppSnackBar.showError(context, error);
      }
    } finally {
      if (mounted) setState(() => _composingFlashback = false);
    }
  }

  Future<void> _refreshPolling() async {
    if (_refreshingPolling) return;
    setState(() => _refreshingPolling = true);
    try {
      await _viewModel?.refreshPaymentPolling();
    } finally {
      if (mounted) setState(() => _refreshingPolling = false);
    }
  }

  @override
  void dispose() {
    PaymentPushCoordinator.instance.registerResultScreenCallback(null);
    _viewModel?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = _viewModel;
    final theme = _theme;
    if (vm == null || theme == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    if (_composingFlashback) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.amber),
              const SizedBox(height: 16),
              Text(
                AppStrings.flashbackComposing,
                style: TextStyle(color: Colors.amber.shade100),
              ),
            ],
          ),
        ),
      );
    }

    return ChangeNotifierProvider<PrePaymentViewModel>.value(
      value: vm,
      child: Scaffold(
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
            'Pay to start',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 20,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: Stack(
          children: [
            Positioned.fill(child: ThemeBackground(theme: theme)),
            SafeArea(
              child: CenteredMaxWidth(
                maxWidth: 520,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: ListenableBuilder(
                    listenable: vm,
                    builder: (context, _) => _PrePaymentCard(
                      viewModel: vm,
                      refreshingPolling: _refreshingPolling,
                      onRetry: () => vm.retryLoadPaymentQr(),
                      onRefreshPolling: _refreshPolling,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrePaymentCard extends StatelessWidget {
  const _PrePaymentCard({
    required this.viewModel,
    required this.refreshingPolling,
    required this.onRetry,
    required this.onRefreshPolling,
  });

  final PrePaymentViewModel viewModel;
  final bool refreshingPolling;
  final VoidCallback onRetry;
  final Future<void> Function() onRefreshPolling;

  @override
  Widget build(BuildContext context) {
    final approved = viewModel.fcmPaymentPushSuccess == true;
    final failed = viewModel.fcmPaymentPushSuccess == false;
    final statusColor = failed
        ? Colors.red.shade200
        : approved
            ? Colors.green.shade200
            : Colors.white.withValues(alpha: 0.85);
    final statusMessage = failed
        ? (viewModel.fcmPaymentStatusDetail ??
            'Payment failed. Please try again.')
        : approved
            ? (viewModel.fcmPaymentStatusDetail ??
                'Payment approved. Starting AI generation…')
            : (viewModel.isPaymentGatewayEnabled
                ? 'Waiting for payment confirmation...'
                : 'Waiting for admin approval...');

    return Container(
      height: 480,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        children: [
          const Text(
            'Pay via UPI',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '₹${viewModel.chargeAmount}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          if (!SessionManager().isOfflineSession)
            ResultPaymentCouponRow(
              appliedDiscount: viewModel.appliedDiscount,
              couponError: viewModel.couponError,
              busy: viewModel.couponBusy || viewModel.paymentInitInProgress,
              onApply: viewModel.applyCoupon,
              onUnapply: viewModel.unapplyCoupon,
            )
          else
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                AppStrings.offlineGiftCardUnavailable,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          const SizedBox(height: 6),
          Expanded(
            child: Center(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                alignment: Alignment.center,
                child: _buildQrArea(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            statusMessage,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: statusColor,
            ),
          ),
          if (viewModel.isDeadPollingFallbackVisible) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                    onPressed: refreshingPolling ? null : onRefreshPolling,
                    child: refreshingPolling
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Refresh'),
                  ),
                ),
              ],
            ),
          ],
          if (viewModel.paymentInitError != null && !approved) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQrArea() {
    if (!viewModel.isPaymentGatewayEnabled) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Image.asset(
          'lib/images/upi_qr_fallback.png',
          fit: BoxFit.contain,
        ),
      );
    }
    if (viewModel.hasPaymentQrPayload) {
      return KioskPaymentQrDisplay(
        qrImageUrl: viewModel.qrImageUrl,
        upiLink: viewModel.upiLink,
        paymentLink: viewModel.paymentLink,
        maxContentWidth: 280,
      );
    }
    if (viewModel.paymentInitInProgress) {
      return const CircularProgressIndicator(strokeWidth: 2);
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        viewModel.paymentInitError ??
            'UPI QR is not ready yet. Tap Retry or ask staff.',
        textAlign: TextAlign.center,
      ),
    );
  }
}
