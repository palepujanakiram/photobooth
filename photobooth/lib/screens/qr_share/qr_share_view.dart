import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_settings_manager.dart';
import '../../services/session_manager.dart';
import '../../services/whatsapp_push_coordinator.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';
import '../../utils/route_args.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';
import '../result/result_viewmodel.dart';
import 'qr_share_copy_helpers.dart';
import 'qr_share_scaffold_body.dart';

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
  int _secondsLeft = AppConstants.kQrShareIdleSeconds;
  bool _exiting = false;

  /// One-shot toast guard: we show the post-receipt outcome dialog at most once
  /// per QR share screen lifecycle.
  bool _postReceiptToastShown = false;
  bool _printKickoffScheduled = false;

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
        printOrientation: SessionManager().printOrientation,
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_printKickoffScheduled) return;
      _printKickoffScheduled = true;
      unawaited(_viewModel?.startPostPaymentPrintIfNeeded());
    });

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

    final expiry = qrShareExpiryText(expiresAt);

    return ChangeNotifierProvider.value(
      value: _viewModel!,
      child: Consumer<ResultViewModel>(
        builder: (context, viewModel, _) {
          final phone = (parsed.customerPhone ?? '').trim();
          final waRequested = viewModel.effectiveWhatsappOptIn;
          final waActuallyQueued = viewModel.whatsappQueued;
          final vmStatus = (viewModel.whatsappDeliveryStatus ?? '').trim();
          final headline = qrShareHeadline(
            waActuallyQueued: waActuallyQueued,
            phone: phone,
          );
          final waLine = qrShareWhatsappLine(
            waActuallyQueued: waActuallyQueued,
            vmStatus: vmStatus,
            waRequested: waRequested,
          );
          return QrShareScaffoldBody(
            qrData: qrData,
            longUrl: longUrl,
            expiry: expiry,
            headline: headline,
            waLine: waLine,
            secondsLeft: _secondsLeft,
            onExit: _exitToStart,
          );
        },
      ),
    );
  }
}

