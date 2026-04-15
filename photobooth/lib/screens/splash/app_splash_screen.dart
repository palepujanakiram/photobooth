import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Colors, Scaffold;

import '../theme_selection/theme_model.dart';
import '../theme_selection/theme_preview_screen.dart';
import 'bootstrap_route_args.dart';
import 'kiosk_qr_scan_screen.dart';
import '../../services/api_service.dart';
import '../../services/kiosk_manager.dart';
import '../../services/session_manager.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/animated_slideshow_background.dart'
    show kSlideshowAssetPaths;

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
    final ok = await _api.validateKioskCode(code);
    if (!mounted) return;
    if (!ok) {
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
    final urls = await _loadThemeBackgroundUrls();
    if (!mounted) return;
    setState(() => _busy = false);
    _goToTerms(urls);
  }

  Future<List<String>> _loadThemeBackgroundUrls() async {
    try {
      final themes = await _api.getThemes();
      final urls = _urlsForSlideshow(themes);
      // Always prefer kiosk-enabled theme samples when available, but if the kiosk
      // has only a few themes, mix in the default slideshow assets to avoid a
      // tiled wallpaper look.
      if (urls.isEmpty) return [];
      if (urls.length >= 6) return urls;
      final mixed = <String>[...urls];
      mixed.addAll(kSlideshowAssetPaths);
      // De-dupe while preserving order (theme samples first).
      final seen = <String>{};
      return mixed.where(seen.add).toList();
    } catch (_) {
      return [];
    }
  }

  List<String> _urlsForSlideshow(List<ThemeModel> themes) {
    final seen = <String>{};
    final out = <String>[];
    for (final t in themes) {
      final u = ThemePreviewScreen.resolveSampleImageUrl(t).trim();
      if (u.isEmpty) continue;
      if (seen.add(u)) out.add(u);
    }
    if (out.isEmpty) return [];
    if (out.length == 1) return [out.first, out.first];
    return out;
  }

  void _goToTerms(List<String> urls) {
    final args = urls.isEmpty
        ? null
        : TermsRouteArgs(backgroundImageUrls: urls);
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
    final ok = await _api.validateKioskCode(code);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'Invalid kiosk code. Check with your venue and try again.';
      });
      return;
    }
    await _kiosk.setKioskCode(code);
    SessionManager().clearSession();
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
    SessionManager().clearSession();
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
                  Text(leftTitle, textAlign: TextAlign.center, style: titleStyle),
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
                  Text(rightTitle, textAlign: TextAlign.center, style: titleStyle),
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
                color:
                    scanDisabled ? CupertinoColors.systemGrey : Colors.black,
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

    return Scaffold(
      backgroundColor: appColors.backgroundColor,
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
                      onPressed: _busy
                          ? null
                          : () => Navigator.of(context).pop(),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: formMaxWidth),
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: appColors.backgroundColor
                                    .withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: appColors.dividerColor
                                      .withValues(alpha: 0.45),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FadeTransition(
                                    opacity: _fade,
                                    child: ScaleTransition(
                                      scale: _scale,
                                      child: Column(
                                        children: [
                                          SizedBox(
                                            height: 72,
                                            child: Image.asset(
                                              AppConstants.kBrandLogoAsset,
                                              fit: BoxFit.contain,
                                              errorBuilder: (_, __, ___) =>
                                                  Icon(
                                                CupertinoIcons.sparkles,
                                                size: 56,
                                                color: appColors.primaryColor,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            AppConstants.kBrandName,
                                            style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w700,
                                              color: appColors.textColor,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            widget.args.manageKiosk
                                                ? 'Kiosk settings'
                                                : (_needsEntry
                                                    ? 'Enter your venue kiosk code to continue'
                                                    : 'Getting things ready…'),
                                            style: TextStyle(
                                              fontSize: 15,
                                              color: appColors
                                                  .secondaryTextColor,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (_bootstrapDone) ...[
                                    const SizedBox(height: 26),
                                    if (showManageSummary) ...[
                                    Text(
                                      'Linked to kiosk',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: appColors.secondaryTextColor,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _storedCode!,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 1.2,
                                        color: appColors.textColor,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 24),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: CupertinoButton(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 14,
                                            ),
                                            color: CupertinoColors.systemBlue,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            onPressed: _busy
                                                ? null
                                                : () => setState(() {
                                                      _manageEditing = true;
                                                      _codeController.text =
                                                          _storedCode ?? '';
                                                    }),
                                            child: const Text(
                                              'Change code',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: CupertinoColors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: CupertinoButton(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 14,
                                            ),
                                            color: CupertinoColors.systemRed
                                                .resolveFrom(context)
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            onPressed:
                                                _busy ? null : _disconnect,
                                            child: Text(
                                              'Disconnect',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: CupertinoColors
                                                    .destructiveRed
                                                    .resolveFrom(context),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (showForm) ...[
                                    if (showManageSummary)
                                      const SizedBox(height: 20),
                                    Text(
                                      'Enter the code, or scan the operator’s QR with this booth',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: appColors.secondaryTextColor,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 10),
                                    _buildCodeOrScanRow(
                                      appColors,
                                      formMaxWidth,
                                      showManageSummary,
                                    ),
                                    if (_error != null) ...[
                                      const SizedBox(height: 10),
                                      Text(
                                        _error!,
                                        style: const TextStyle(
                                          color: CupertinoColors.systemRed,
                                          fontSize: 14,
                                          height: 1.3,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                    const SizedBox(height: 18),
                                    CupertinoButton(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      color: CupertinoColors.systemBlue,
                                      borderRadius: BorderRadius.circular(12),
                                      onPressed: _busy ? null : _submitCode,
                                      child: Text(
                                        widget.args.manageKiosk
                                            ? 'Save & continue'
                                            : 'Continue',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: CupertinoColors.white,
                                        ),
                                      ),
                                    ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
