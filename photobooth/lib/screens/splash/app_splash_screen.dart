import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:provider/provider.dart';

import 'bootstrap_route_args.dart';
import 'kiosk_qr_scan_screen.dart';
import '../../models/kiosk_device_status.dart';
import '../../models/kiosk_info_model.dart';
import '../../services/api_service.dart';
import '../../services/app_settings_manager.dart';
import '../../services/client_identification.dart';
import '../../services/customer_session_lifecycle.dart';
import '../../services/kiosk_manager.dart';
import '../../services/event_manager.dart';
import '../../services/kiosk_device_status_service.dart';
import '../../utils/constants.dart';
import '../../utils/kiosk_qr_payload.dart';
import '../../utils/logger.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/animated_slideshow_background.dart'
    show kSlideshowAssetPaths;
import 'app_splash_event_helpers.dart';
import 'app_splash_input_helpers.dart';
import 'app_splash_screen_body.dart';
import '../../utils/event_station_role.dart';
import '../../utils/kiosk_runtime_refresh.dart';

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
  late final TextEditingController _eventController;

  final ApiService _api = ApiService();
  final KioskManager _kiosk = KioskManager();
  final EventManager _event = EventManager();

  bool _busy = false;
  String? _error;
  bool _bootstrapDone = false;
  String? _storedCode;
  bool _needsEntry = false;
  bool _manageEditing = false;
  bool _deviceStatusLoading = false;
  KioskDeviceStatusSnapshot? _deviceStatus;
  final KioskDeviceStatusService _deviceStatusService = KioskDeviceStatusService();

  @override
  void initState() {
    super.initState();
    _splashStart = DateTime.now();
    _codeController = TextEditingController();
    _eventController = TextEditingController();
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
    _eventController.dispose();
    super.dispose();
  }

  Future<void> _ensureMinSplashElapsed() async {
    const minDur = Duration(milliseconds: 1400);
    final elapsed = DateTime.now().difference(_splashStart);
    if (elapsed < minDur) {
      await Future<void>.delayed(minDur - elapsed);
    }
  }

  /// Reload `/api/settings?kiosk=` so guest prices and flags match this kiosk.
  Future<void> _refreshSettingsForBoundKiosk({
    Duration timeout = kKioskSettingsRefreshTimeout,
  }) async {
    if (!mounted) return;
    await refreshBoundKioskAppSettings(
      settings: context.read<AppSettingsManager>(),
      timeout: timeout,
    );
  }

  /// Re-probe DNP / receipt / USB / DSLR. When [forceSettingsRefresh] is true
  /// (manual Refresh / manage open), reload `/api/settings` first so transport
  /// / host changes from ZenAI apply before probing.
  Future<void> _refreshDeviceStatus({
    bool forceSettingsRefresh = false,
  }) async {
    if (!mounted || !widget.args.manageKiosk) return;
    setState(() => _deviceStatusLoading = true);
    try {
      if (forceSettingsRefresh) {
        await _refreshSettingsForBoundKiosk(
          timeout: const Duration(seconds: 8),
        );
        if (!mounted) return;
      }
      final settings = context.read<AppSettingsManager>().settings;
      final snapshot = await _deviceStatusService
          .probe(settings: settings)
          .timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() => _deviceStatus = snapshot);
    } on TimeoutException catch (e, st) {
      AppLogger.warning(
        'Kiosk device status refresh timed out',
        error: e,
        stackTrace: st,
      );
    } catch (e, st) {
      AppLogger.warning(
        'Kiosk device status refresh failed',
        error: e,
        stackTrace: st,
      );
    } finally {
      if (mounted) {
        setState(() => _deviceStatusLoading = false);
      }
    }
  }

  Future<void> _onRefreshDeviceStatusPressed() async {
    await _refreshDeviceStatus(forceSettingsRefresh: true);
  }

  Future<void> _bootstrapDeviceStatus() async {
    // One pass only — a second probe while native USB from the first is still
    // winding down has frozen Android TV USB (DNP + UVC).
    await _refreshDeviceStatus(forceSettingsRefresh: true);
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
      if ((code ?? '').trim().isNotEmpty) {
        unawaited(_bootstrapDeviceStatus());
      }
      return;
    }

    // On web, allow the booth to provision itself via URL query, e.g.
    // `...?kioskCode=ABCD&source=kiosk` so analytics can distinguish kiosk vs web.
    if (kIsWeb) {
      final qp = Uri.base.queryParameters;
      final fromUrl =
          (qp['kioskCode'] ?? qp['code'] ?? '').trim().toUpperCase();
      final eventFromUrl =
          (qp['eventCode'] ?? qp['event'] ?? '').trim().toUpperCase();
      if (fromUrl.isNotEmpty) {
        await _kiosk.setKioskCode(fromUrl);
        await endPhotoboothCustomerSessionLogged(
          'splash: web kiosk code from URL',
        );
        await _refreshSettingsForBoundKiosk();
      }
      if (eventFromUrl.isNotEmpty) {
        await _event.setEventCode(eventFromUrl);
        _eventController.text = eventFromUrl;
      }
    }

    final raw = await _kiosk.getKioskCode();
    final trimmed = (raw ?? '').trim();
    final storedEvent = await _event.getEventCode();
    if (!mounted) return;
    if (storedEvent != null && storedEvent.isNotEmpty) {
      _eventController.text = storedEvent;
    }

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
    try {
      final kiosk = await _fetchKioskByCodeBounded(code);
      if (!mounted) return;
      if (kiosk == null) {
        setState(() {
          _bootstrapDone = true;
          _needsEntry = true;
          _error =
              'Could not verify kiosk code. Check network and try again, or enter a new code.';
          _codeController.text = code;
        });
        return;
      }
      await _kiosk.setKioskCode(code);
      await _kiosk.setPaymentEnabledOverride(kiosk.paymentEnabled);
      await _kiosk.setClassicPhotosEnabled(kiosk.classicPhotosEnabled);
      final eventErr = await bindSplashEventCode(
        eventManager: _event,
        fetchEvent: (code, kioskCode) =>
            _api.fetchEventByCode(code, kioskCode: kioskCode),
        eventCode: _eventController.text,
        kioskCode: code,
      );
      if (!mounted) return;
      if (eventErr != null) {
        setState(() {
          _bootstrapDone = true;
          _needsEntry = true;
          _error = eventErr;
          _codeController.text = code;
        });
        return;
      }
      await _refreshSettingsForBoundKiosk();
      final urls = await _loadThemeBackgroundUrls();
      if (!mounted) return;
      await _goAfterBind(urls);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Splash must not sit on [_busy] for the full Dio 5‑minute API timeout —
  /// that freezes the kiosk-code field under an overlay (feels hung).
  Future<KioskInfoModel?> _fetchKioskByCodeBounded(String code) async {
    try {
      return await _api.fetchKioskByCode(code).timeout(
        const Duration(seconds: 12),
        onTimeout: () {
          AppLogger.warning(
            'Splash fetchKioskByCode timed out after 12s for ${code.trim()}',
          );
          return null;
        },
      );
    } catch (e, st) {
      AppLogger.warning(
        'Splash fetchKioskByCode failed',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  Future<void> _goAfterBind(List<String> urls) async {
    final eventCode = await _event.getEventCode();
    final role = await _event.getStationRole();
    if (!mounted) return;
    final dest = resolveEventPostSplashRoute(
      eventCode: eventCode,
      stationRole: role,
    );
    if (dest == EventPostSplashRoute.terms) {
      _goToTerms(urls);
      return;
    }
    Navigator.pushReplacementNamed(context, eventPostSplashRouteName(dest));
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
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final kiosk = await _fetchKioskByCodeBounded(code);
      if (!mounted) return;
      if (kiosk == null) {
        setState(() {
          _error =
              'Invalid kiosk code or network timeout. Check with your venue and try again.';
        });
        return;
      }
      await _kiosk.setKioskCode(code);
      await _kiosk.setPaymentEnabledOverride(kiosk.paymentEnabled);
      await _kiosk.setClassicPhotosEnabled(kiosk.classicPhotosEnabled);
      await endPhotoboothCustomerSessionLogged('splash: kiosk code submitted');
      final eventErr = await bindSplashEventCode(
        eventManager: _event,
        fetchEvent: (eventCode, kioskCode) =>
            _api.fetchEventByCode(eventCode, kioskCode: kioskCode),
        eventCode: _eventController.text,
        kioskCode: code,
      );
      if (!mounted) return;
      if (eventErr != null) {
        setState(() => _error = eventErr);
        return;
      }
      await _refreshSettingsForBoundKiosk();
      final urls = await _loadThemeBackgroundUrls();
      if (!mounted) return;
      await _goAfterBind(urls);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final kiosk = KioskQrPayload.parse(code) ?? code.trim().toUpperCase();
    final event = KioskQrPayload.parseEventCode(code);
    _codeController.value = TextEditingValue(
      text: kiosk,
      selection: TextSelection.collapsed(offset: kiosk.length),
    );
    if (event != null) {
      _eventController.text = event;
    }
    await _submitCode();
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    await _kiosk.clearKioskCode();
    await _kiosk.clearPaymentEnabledOverride();
    await _kiosk.clearClassicPhotosEnabled();
    await _event.clearEvent();
    await endPhotoboothCustomerSessionLogged('splash: kiosk disconnect');
    if (!mounted) return;
    setState(() {
      _busy = false;
      _storedCode = null;
      _codeController.clear();
      _eventController.clear();
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
    // Do not rewrite [TextEditingController] in onChanged — clearing IME
    // composing / jumping selection freezes typing on Android soft keyboards.
    // Uppercase on submit (and textCapitalization) is enough.
    final textField = CupertinoTextField(
      controller: _codeController,
      placeholder: 'Kiosk code',
      autofocus: !showManageSummary,
      enabled: splashCodeFieldEnabled(busy: _busy, showForm: true),
      textAlign: TextAlign.start,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      autocorrect: false,
      enableSuggestions: false,
      textCapitalization: TextCapitalization.characters,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      style: TextStyle(fontSize: 17, color: appColors.textColor),
      onChanged: (_) {
        if (_error != null) {
          setState(() => _error = null);
        }
      },
      onSubmitted: (_) {
        if (!_busy) unawaited(_submitCode());
      },
    );

    const enterSubtitle = 'Type or paste the kiosk ID';
    const scanSubtitle = kIsWeb
        ? 'Use booth Android/iOS app to scan the operator’s QR'
        : 'Point booth camera at the QR on the operator’s phone';

    final sideBySide = formMaxWidth >= 360;
    Widget kioskRow = _kioskOptionCard(
      appColors: appColors,
      title: 'Enter code',
      subtitle: enterSubtitle,
      child: textField,
    );
    if (false) {
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
                    color: scanDisabled
                        ? CupertinoColors.systemGrey
                        : Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      kioskRow = sideBySide
          ? _kioskOptionPairSideBySide(
              appColors: appColors,
              leftTitle: 'Enter code',
              rightTitle: 'Scan QR',
              leftSubtitle: enterSubtitle,
              rightSubtitle: scanSubtitle,
              leftChild: textField,
              rightChild: scanTap,
            )
          : Column(
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        kioskRow,
        if (false) ...[
          const SizedBox(height: 12),
          Text(
            'Have an event code?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: appColors.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 8),
          CupertinoTextField(
            controller: _eventController,
            placeholder: 'Event code (optional)',
            enabled: splashCodeFieldEnabled(busy: _busy, showForm: true),
            textAlign: TextAlign.start,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            style: TextStyle(fontSize: 17, color: appColors.textColor),
            onSubmitted: (_) {
              if (!_busy) unawaited(_submitCode());
            },
          ),
        ],
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
                    deviceStatusLoading: _deviceStatusLoading,
                    deviceStatus: _deviceStatus,
                    onRefreshDeviceStatus: _onRefreshDeviceStatusPressed,
                  ),
                ),
                appSplashVersionFooter(versionFooter, appColors),
              ],
            ),
            if (splashShouldBlockWithBusyOverlay(
              busy: _busy,
              showForm: showForm,
            ))
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
