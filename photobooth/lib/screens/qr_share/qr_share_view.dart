import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_settings_manager.dart';
import '../../services/session_manager.dart';
import '../../services/whatsapp_push_coordinator.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/kiosk_offline_ux.dart';
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
  late final ValueNotifier<int> _secondsLeft;
  bool _offline = false;
  bool _exiting = false;
  QrShareArgs? _parsedArgs;

  /// One-shot toast guard: we show the post-receipt outcome dialog at most once
  /// per QR share screen lifecycle.
  bool _postReceiptToastShown = false;
  bool _printKickoffScheduled = false;
  bool _shareArtifactsKickoffScheduled = false;

  void _onWhatsappStatusFromFcm(WhatsAppStatusPayload payload) {
    _viewModel?.applyWhatsappStatusPush(payload);
  }

  @override
  void initState() {
    super.initState();
    _offline = KioskOfflineUx.shouldUseOfflineQrShareUx(
      sessionOffline: SessionManager().isOfflineSession,
    );
    _secondsLeft = ValueNotifier<int>(
      KioskOfflineUx.qrShareIdleSeconds(sessionOffline: _offline),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final parsed =
        QrShareArgs.tryParse(ModalRoute.of(context)?.settings.arguments);
    if (parsed == null) return;
    _parsedArgs = parsed;

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

    _viewModel?.enterGuestQrShareMode();

    if (!_offline) {
      WhatsAppPushCoordinator.instance
          .registerCallback(_onWhatsappStatusFromFcm);
      _viewModel?.startWhatsappDeliveryPolling();
      _viewModel?.addListener(_maybeShowPostReceiptToast);
      _maybeShowPostReceiptToast();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_printKickoffScheduled) return;
      _printKickoffScheduled = true;
      unawaited(_viewModel?.startPostPaymentPrintIfNeeded());
      if (!_offline) {
        _scheduleShareArtifactsKickoffIfNeeded();
      }
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft.value <= 1) {
        t.cancel();
        unawaited(_exitToStart());
        return;
      }
      _secondsLeft.value -= 1;
    });
  }

  void _scheduleShareArtifactsKickoffIfNeeded() {
    if (_shareArtifactsKickoffScheduled || _viewModel == null) return;
    final parsed = _parsedArgs;
    if (parsed == null) return;

    final snapshot = QrShareUiSnapshot.fromViewModel(
      viewModel: _viewModel!,
      parsedShareUrl: parsed.shareUrl,
      parsedKioskShareUrl: parsed.kioskShareUrl,
      parsedShareLongUrl: parsed.shareLongUrl,
      parsedShareExpiresAt: parsed.shareExpiresAt,
      phone: (parsed.customerPhone ?? '').trim(),
      offline: _offline,
    );
    if (snapshot.qrData.isNotEmpty) return;

    _shareArtifactsKickoffScheduled = true;
    unawaited(_viewModel!.ensurePostPaymentShareArtifacts());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _secondsLeft.dispose();
    WhatsAppPushCoordinator.instance.registerCallback(null);
    _viewModel?.removeListener(_maybeShowPostReceiptToast);
    _viewModel?.stopWhatsappDeliveryPolling();
    if (_ownsViewModel) {
      _viewModel?.dispose();
    }
    super.dispose();
  }

  /// Watches [ResultViewModel.postReceiptOutcome] and shows the one-shot toast
  /// once when the value transitions out of [PostReceiptOutcome.pending].
  void _maybeShowPostReceiptToast() {
    if (_offline || _postReceiptToastShown) return;
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
    final vm = _viewModel;
    if (!mounted) return;
    unawaited(
      vm?.privacyWipeLocal().catchError((Object e, StackTrace st) {
        AppLogger.debug('Privacy wipe (qr-share) failed: $e\n$st');
      }),
    );
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
    final parsed = _parsedArgs;

    if (!_initialized || _viewModel == null || parsed == null) {
      return Scaffold(
        backgroundColor: appColors.backgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final phone = (parsed.customerPhone ?? '').trim();

    return ChangeNotifierProvider.value(
      value: _viewModel!,
      child: Selector<ResultViewModel, QrShareUiSnapshot>(
        selector: (_, viewModel) => QrShareUiSnapshot.fromViewModel(
          viewModel: viewModel,
          parsedShareUrl: parsed.shareUrl,
          parsedKioskShareUrl: parsed.kioskShareUrl,
          parsedShareLongUrl: parsed.shareLongUrl,
          parsedShareExpiresAt: parsed.shareExpiresAt,
          phone: phone,
          offline: _offline,
        ),
        builder: (context, snapshot, _) {
          return QrShareScaffoldBody(
            qrData: snapshot.qrData,
            longUrl: snapshot.longUrl,
            expiry: qrShareExpiryText(snapshot.expiresAt),
            headline: snapshot.headline,
            waLine: snapshot.waLine,
            offline: snapshot.offline,
            appBarTitle: snapshot.offline
                ? AppStrings.qrShareOfflineAppBarTitle
                : null,
            secondsLeftListenable: _secondsLeft,
            onExit: () => unawaited(_exitToStart()),
          );
        },
      ),
    );
  }
}
