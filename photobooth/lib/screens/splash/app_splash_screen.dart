import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Colors, Scaffold;

import 'bootstrap_route_args.dart';
import 'kiosk_qr_scan_screen.dart';
import '../../services/api_service.dart';
import '../../services/client_identification.dart';
import '../../services/customer_session_lifecycle.dart';
import '../../services/kiosk_manager.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/animated_slideshow_background.dart'
    show kSlideshowAssetPaths;
import 'app_splash_screen_body.dart';

/// Cold start and kiosk management: branded animation, no stacked dialogs.
class AppSplashScreen extends StatefulWidget {
  const AppSplashScreen({super.key, required this.args});

  final SplashRouteArgs args;

  @override
  State<AppSplashScreen> createState() => _AppSplashScreenState();
}

class _AppSplashScreenState extends State<AppSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _logoController;
  late final Animation<double> _fade;
  late final Animation<double> _scale;
  late final DateTime _splashStart;
  late final TextEditingController _codeController;

  final ApiService _api = ApiService();
  final KioskManager _kiosk = KioskManager();

  bool _busy = false;
  String? _error;
  bool _bootstrapDone = false;
  String? _storedCode;
  bool _needsEntry = false;
  bool _manageEditing = false;

  @override
  void initState() {
    super.initState();
    _splashStart = DateTime.now();
    _codeController = TextEditingController();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _fade = CurvedAnimation(parent: _logoController, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutCubic),
    );
    _logoController.forward();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _logoController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _ensureMinSplashElapsed() async {
    const minDur = Duration(milliseconds: 1400);
    final elapsed = DateTime.now().difference(_splashStart);
    if (elapsed < minDur) {
      await Future<void>.delayed(minDur - elapsed);
    }
  }

  Future<void> _bootstrap() async {
    await _ensureMinSplashElapsed();
    if (!mounted) return;

    if (widget.args.manageKiosk) {
      final code = await _kiosk.getKioskCode();
      if (!mounted) return;
      setState(() {
        _bootstrapDone = true;
        _storedCode = code;
        _codeController.text = (code ?? '').trim();
      });
      return;
    }

    // On web, allow the booth to provision itself via URL query, e.g.
    // `...?kioskCode=ABCD&source=kiosk` so analytics can distinguish kiosk vs web.
    if (kIsWeb) {
      final qp = Uri.base.queryParameters;
      final fromUrl =
          (qp['kioskCode'] ?? qp['code'] ?? '').trim().toUpperCase();
      if (fromUrl.isNotEmpty) {
        await _kiosk.setKioskCode(fromUrl);
        await endPhotoboothCustomerSessionLogged(
          'splash: web kiosk code from URL',
        );
      }
    }

    final raw = await _kiosk.getKioskCode();
    final trimmed = (raw ?? '').trim();
    if (!mounted) return;

    if (trimmed.isEmpty) {
      setState(() {
        _bootstrapDone = true;
        _needsEntry = true;
      });
      return;
    }

    await _tryProceedWithStoredCode(trimmed);
  }

  Future<void> _tryProceedWithStoredCode(String code) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final kiosk = await _api.fetchKioskByCode(code);
    if (!mounted) return;
    if (kiosk == null) {
      setState(() {
        _busy = false;
        _bootstrapDone = true;
        _needsEntry = true;
        _error = 'Stored kiosk code is no longer valid. Enter a new code.';
        _codeController.text = code;
      });
      return;
    }
    await _kiosk.setKioskCode(code);
    await _kiosk.setPaymentEnabledOverride(kiosk.paymentEnabled);
    final urls = await _loadThemeBackgroundUrls();
    if (!mounted) return;
    setState(() => _busy = false);
    _goToTerms(urls);
  }

  /// Bundled slideshow assets load instantly; theme API samples are not used here.
  Future<List<String>> _loadThemeBackgroundUrls() async {
    return List<String>.from(kSlideshowAssetPaths);
  }

  void _goToTerms(List<String> urls) {
    final args =
        urls.isEmpty ? null : TermsRouteArgs(backgroundImageUrls: urls);
    Navigator.pushReplacementNamed(
      context,
      AppConstants.kRouteTerms,
      arguments: args,
    );
  }

  Future<void> _submitCode() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Enter a kiosk code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final kiosk = await _api.fetchKioskByCode(code);
    if (!mounted) return;
    if (kiosk == null) {
      setState(() {
        _busy = false;
        _error = 'Invalid kiosk code. Check with your venue and try again.';
      });
      return;
    }
    await _kiosk.setKioskCode(code);
    await _kiosk.setPaymentEnabledOverride(kiosk.paymentEnabled);
    await endPhotoboothCustomerSessionLogged('splash: kiosk code submitted');
    final urls = await _loadThemeBackgroundUrls();
    if (!mounted) return;
    setState(() => _busy = false);
    _goToTerms(urls);
  }

  Future<void> _openQrScanner() async {
    if (kIsWeb) return;
    final code = await Navigator.of(context).push<String>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (context) => const KioskQrScanScreen(),
      ),
    );
    if (!mounted || code == null) return;
    _codeController.value = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
    await _submitCode();
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    await _kiosk.clearKioskCode();
    await _kiosk.clearPaymentEnabledOverride();
    await endPhotoboothCustomerSessionLogged('splash: kiosk disconnect');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _storedCode = null;
      _codeController.clear();
      _manageEditing = true;
      _error = null;
    });
  }

  BoxDecoration _kioskOptionBoxDecoration(AppColors appColors) {
    return BoxDecoration(
      color: appColors.cardBackgroundColor.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: appColors.dividerColor.withValues(alpha: 0.55),
      ),
    );
  }

  /// Stacked layout (narrow): title + subtitle + field in one card.
  Widget _kioskOptionCard({
    required AppColors appColors,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      constraints: const BoxConstraints(minHeight: 132),
      decoration: _kioskOptionBoxDecoration(appColors),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: appColors.textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              color: appColors.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 56, child: child),
        ],
      ),
    );
  }

  /// Side-by-side: titles share one row, subtitles share one row, fields align.
  Widget _kioskOptionPairSideBySide({
    required AppColors appColors,
    required String leftTitle,
    required String rightTitle,
    required String leftSubtitle,
    required String rightSubtitle,
    required Widget leftChild,
    required Widget rightChild,
  }) {
    final titleStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: appColors.textColor,
    );
    final subtitleStyle = TextStyle(
      fontSize: 12,
      height: 1.3,
      color: appColors.secondaryTextColor,
    );
    const subtitleSlotHeight = 52.0;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: _kioskOptionBoxDecoration(appColors),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(leftTitle,
                      textAlign: TextAlign.center, style: titleStyle),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: subtitleSlotHeight,
                    child: Text(
                      leftSubtitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(height: 56, child: leftChild),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: _kioskOptionBoxDecoration(appColors),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(rightTitle,
                      textAlign: TextAlign.center, style: titleStyle),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: subtitleSlotHeight,
                    child: Text(
                      rightSubtitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: subtitleStyle,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(height: 56, child: rightChild),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Side-by-side on wide layouts; stacked on narrow phones.
  Widget _buildCodeOrScanRow(
    AppColors appColors,
    double formMaxWidth,
    bool showManageSummary,
  ) {
    const inputHeight = 56.0;
    final textField = CupertinoTextField(
      controller: _codeController,
      placeholder: 'Kiosk code',
      autofocus: !showManageSummary,
      enabled: !_busy,
      textAlign: TextAlign.start,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.characters,
      textInputAction: TextInputAction.done,
      style: TextStyle(fontSize: 17, color: appColors.textColor),
      onChanged: (v) {
        if (_error != null) {
          setState(() => _error = null);
        }
        final up = v.toUpperCase();
        if (up != v) {
          _codeController.value = _codeController.value.copyWith(
            text: up,
            selection: TextSelection.collapsed(offset: up.length),
            composing: TextRange.empty,
          );
        }
      },
      onSubmitted: (_) => _submitCode(),
    );

    final scanDisabled = _busy || kIsWeb;
    final scanTap = Semantics(
      button: true,
      label: kIsWeb
          ? 'QR scanning is not available on web'
          : 'Aim booth camera at QR on operator phone to link',
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        color: Colors.transparent,
        pressedOpacity: scanDisabled ? 1.0 : 0.85,
        onPressed: scanDisabled ? null : _openQrScanner,
        child: Container(
          width: double.infinity,
          height: inputHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  scanDisabled ? CupertinoColors.systemGrey3 : Colors.black12,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.qrcode_viewfinder,
                size: 24,
                color: scanDisabled ? CupertinoColors.systemGrey : Colors.black,
              ),
              const SizedBox(width: 8),
              Text(
                'Scan phone QR',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color:
                      scanDisabled ? CupertinoColors.systemGrey : Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    const enterSubtitle = 'Type or paste the kiosk ID';
    const scanSubtitle = kIsWeb
        ? 'Use booth Android/iOS app to scan the operator’s QR'
        : 'Point booth camera at the QR on the operator’s phone';

    final sideBySide = formMaxWidth >= 360;

    if (sideBySide) {
      return _kioskOptionPairSideBySide(
        appColors: appColors,
        leftTitle: 'Enter code',
        rightTitle: 'Scan QR',
        leftSubtitle: enterSubtitle,
        rightSubtitle: scanSubtitle,
        leftChild: textField,
        rightChild: scanTap,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kioskOptionCard(
          appColors: appColors,
          title: 'Enter code',
          subtitle: enterSubtitle,
          child: textField,
        ),
        const SizedBox(height: 12),
        _kioskOptionCard(
          appColors: appColors,
          title: 'Scan QR',
          subtitle: scanSubtitle,
          child: scanTap,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    // Standard form width (caps tablet/desktop; phones use width minus padding).
    final formMaxWidth = min(400.0, screenWidth - 56);
    final showForm = widget.args.manageKiosk
        ? (_manageEditing || (_storedCode ?? '').isEmpty)
        : _needsEntry;
    final showManageSummary = widget.args.manageKiosk &&
        _bootstrapDone &&
        !_manageEditing &&
        (_storedCode ?? '').isNotEmpty;
    final versionFooter = ClientIdentification.versionFooterLabel;

    return Scaffold(
      backgroundColor: appColors.backgroundColor,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.args.manageKiosk)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CupertinoNavigationBarBackButton(
                      color: CupertinoColors.activeBlue,
                      onPressed:
                          _busy ? null : () => Navigator.of(context).pop(),
                    ),
                  ),
                Expanded(
                  child: AppSplashScreenBody(
                    args: widget.args,
                    appColors: appColors,
                    formMaxWidth: formMaxWidth,
                    fade: _fade,
                    scale: _scale,
                    bootstrapDone: _bootstrapDone,
                    showForm: showForm,
                    showManageSummary: showManageSummary,
                    storedCode: _storedCode,
                    busy: _busy,
                    error: _error,
                    needsEntry: _needsEntry,
                    onManageEdit: () => setState(() {
                      _manageEditing = true;
                      _codeController.text = _storedCode ?? '';
                    }),
                    onDisconnect: _disconnect,
                    buildCodeOrScanRow: (showManageSummary) =>
                        _buildCodeOrScanRow(
                      appColors,
                      formMaxWidth,
                      showManageSummary,
                    ),
                    onSubmitCode: _submitCode,
                    onStaffLogin: () => Navigator.of(context)
                        .pushNamed(AppConstants.kRouteStaffLogin),
                  ),
                ),
                appSplashVersionFooter(versionFooter, appColors),
              ],
            ),
            if (_busy)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.25),
                  child: const Center(
                    child: CupertinoActivityIndicator(radius: 18),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
