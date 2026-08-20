import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Colors, Divider, Orientation, Scaffold, CircularProgressIndicator, RouteSettings;
import 'package:provider/provider.dart';
import 'terms_and_conditions_viewmodel.dart';
import 'terms_camera_priming.dart';
import 'terms_layout_metrics.dart';
import '../../utils/constants.dart';
import '../../utils/app_strings.dart';
import '../../utils/capture_session_kind.dart';
import '../../utils/camera_permission_helper.dart';
import '../../utils/platform_capabilities.dart';
import '../../utils/device_classifier.dart';
import '../../utils/kiosk_page_route.dart';
import '../experience_choice/experience_choice_view.dart';
import '../photo_capture/capture_screen_factory.dart';
import '../photo_capture/photo_capture_pose_setup_helpers.dart';
import '../photo_capture/photo_capture_uvc_device_helpers.dart';
import '../photo_capture/photo_capture_viewmodel.dart';
import '../splash/bootstrap_route_args.dart';
import '../webview/webview_screen.dart';
import '../../services/app_settings_manager.dart';
import '../../services/api_service.dart';
import '../../services/kiosk_manager.dart';
import '../../services/local_camera_service.dart';
import '../../services/fcm_service.dart';
import '../../utils/camera_sidecar_config.dart';
import '../../utils/camera_source_config.dart';
import '../../utils/canon_usb_permission.dart';
import '../../utils/canon_stack_sync.dart';
import '../../utils/kiosk_runtime_refresh.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/full_screen_loader.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/animated_slideshow_background.dart';
import '../../views/widgets/centered_max_width.dart';

class TermsAndConditionsScreen extends StatefulWidget {
  /// Theme sample image URLs for the animated background; null uses default assets.
  final List<String>? backgroundImageUrls;

  const TermsAndConditionsScreen({
    super.key,
    this.backgroundImageUrls,
  });

  @override
  State<TermsAndConditionsScreen> createState() =>
      _TermsAndConditionsScreenState();
}

class _TermsAndConditionsScreenState extends State<TermsAndConditionsScreen> {
  late TermsAndConditionsViewModel _viewModel;
  bool _redirectingToSplash = false;
  bool _navigatingToCapture = false;
  bool _startingExperience = false;
  Object? _capturePrefillPhoto;
  TermsCameraPrimingPhase _cameraPrimingPhase = TermsCameraPrimingPhase.detecting;

  bool _canStartExperience(bool photoUploadAllowed) =>
      !_navigatingToCapture &&
      !_startingExperience &&
      termsCameraPrimingAllowsContinue(
        phase: _cameraPrimingPhase,
        photoUploadAllowed: photoUploadAllowed,
      );

  String _termsStartOverlayText(bool isSubmitting) {
    if (isSubmitting) return AppStrings.termsCreatingSession;
    return AppStrings.termsRefreshingSettings;
  }

  @override
  void initState() {
    super.initState();
    _viewModel = TermsAndConditionsViewModel();
    if (!supportsTermsCameraPriming) {
      _cameraPrimingPhase = TermsCameraPrimingPhase.skipped;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_launchTermsSetup());
    });
  }

  /// Canon USB allow → push permission → camera priming (sequential, no dialog races).
  Future<void> _launchTermsSetup() async {
    if (mounted && supportsTermsCameraPriming) {
      setState(() => _cameraPrimingPhase = TermsCameraPrimingPhase.detecting);
    }

    if (mounted && defaultTargetPlatform == TargetPlatform.android) {
      final settings = context.read<AppSettingsManager>().settings;
      // Stop EDSDK sidecar before PTP touches USB (async settings sync used to race POSE).
      await syncCanonCameraStackForSettings(settings);
      if (usesDirectPtpCamera(settings: settings)) {
        await primeDirectPtpOnTermsLaunch(settings: settings);
      } else if (isDirectCanonSidecarBooth(settings)) {
        await primeCanonUsbOnTermsLaunch(settings: settings);
      }
      await FcmService.ensurePermissionAndPersistToken();
    }

    await _primeCaptureScreenOnLaunch();
  }

  /// Permission, enumeration, and live-camera prewarm while the guest reads terms.
  Future<void> _primeCaptureScreenOnLaunch() async {
    if (!supportsTermsCameraPriming) return;

    if (mounted &&
        _cameraPrimingPhase != TermsCameraPrimingPhase.detecting) {
      setState(() => _cameraPrimingPhase = TermsCameraPrimingPhase.detecting);
    }

    final result = await runTermsCameraPriming(
      ensurePermission: () async {
        if (!mounted) return false;
        final settings = context.read<AppSettingsManager>().settings;
        // Native PTP owns USB only when a Canon is attached — otherwise request
        // CameraX permission so tablets/phones can fall back to device camera.
        if (usesDirectPtpCamera(settings: settings) &&
            await isDirectPtpHardwareAvailable(settings: settings)) {
          return true;
        }
        // Direct EDSDK: skip CameraX permission when localhost sidecar is up.
        if (isDirectCanonSidecarBooth(settings) &&
            await _probeSidecarHealthyForTerms()) {
          return true;
        }
        return ensureCameraPermission();
      },
      preloadCameras: CaptureViewModel.preloadCameras,
      classifyDevice: () async {
        if (!mounted) return null;
        return DeviceClassifier.getDeviceType(context);
      },
      startPrewarm: (deviceType) async {
        if (shouldSkipTermsCameraPrewarm(deviceType)) return;
        await CaptureViewModel.prewarmLiveCamera(deviceType: deviceType);
      },
      hasOpenableCamera: (deviceType) =>
          CaptureViewModel.hasOpenableCaptureCamera(deviceType: deviceType),
      isCameraPlatform: supportsTermsCameraPriming,
      // HDMI capture cards rarely appear in CameraX on Android TV — UVC counts.
      probeAttachedUvc: hasAttachedUvcDevices,
      // Pi DSLR booth: healthy sidecar is enough to Continue (POSE opens HDMI).
      probeSidecarHealthy: _probeSidecarHealthyForTerms,
      ensureCanonUsbPermission: _ensureCanonUsbPermissionForTerms,
    );

    if (!mounted) return;
    setState(() => _cameraPrimingPhase = result.phase);
  }

  Future<bool> _ensureCanonUsbPermissionForTerms() async {
    if (!mounted) return false;
    final settings = context.read<AppSettingsManager>().settings;
    if (usesDirectPtpCamera(settings: settings)) {
      return ensureDirectPtpUsbOnTerms(settings: settings);
    }
    return ensureCanonUsbPermissionForDirectSidecar(settings: settings);
  }

  Future<bool> _probeSidecarHealthyForTerms() async {
    if (!mounted) return false;
    final settings = context.read<AppSettingsManager>().settings;
    if (usesDirectPtpCamera(settings: settings)) {
      return isDirectPtpReadyForTerms(settings: settings);
    }
    if (isDirectCanonSidecarBooth(settings)) {
      return warmDirectSidecarAfterUsbGrant(settings: settings);
    }
    final service = LocalCameraService(
      config: resolveCameraSidecarConfig(settings),
    );
    if (!service.isConfigured && !service.hasSidecarEndpoint) {
      service.dispose();
      return false;
    }
    try {
      final ok = await service.isHealthy().timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );
      service.dispose();
      return ok;
    } on Object {
      service.dispose();
      return false;
    }
  }

  Future<void> _retryCameraPriming() async {
    if (!supportsTermsCameraPriming) return;
    setState(() => _cameraPrimingPhase = TermsCameraPrimingPhase.detecting);
    await _primeCaptureScreenOnLaunch();
  }

  void _redirectToSplashForKioskSetup() {
    if (_redirectingToSplash || !mounted) return;
    _redirectingToSplash = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppConstants.kRouteSplash);
    });
  }

  @override
  void dispose() {
    if (!_navigatingToCapture) {
      unawaited(CaptureViewModel.disposePrewarm());
    }
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _handleAccept() async {
    if (_startingExperience) return;
    setState(() => _startingExperience = true);
    try {
      await _startExperienceAfterRuntimeRefresh();
    } finally {
      if (mounted && !_navigatingToCapture) {
        setState(() => _startingExperience = false);
      }
    }
  }

  /// Pull latest ZenAI settings + Classic flag, then create the guest session.
  Future<void> _startExperienceAfterRuntimeRefresh() async {
    final runtime = await refreshKioskRuntimeConfig(
      settings: context.read<AppSettingsManager>(),
      api: ApiService(),
      kiosk: KioskManager(),
    );
    if (!mounted) return;

    final success =
        await _viewModel.acceptTermsAndCreateSession(_viewModel.kioskCode);

    if (success && mounted) {
      // Keep camera prewarm alive for the AI capture path.
      _navigatingToCapture = true;
      if (runtime.classicPhotosEnabled) {
        await pushReplacementKioskFade<void, void>(
          context,
          ExperienceChoiceScreen(capturePrefillPhoto: _capturePrefillPhoto),
          settings: const RouteSettings(
            name: AppConstants.kRouteExperienceChoice,
          ),
        );
      } else {
        final prefill = _capturePrefillPhoto;
        await pushReplacementKioskFade<void, void>(
          context,
          buildCaptureScreen(
            key: ValueKey<Object?>('ai-pose-${prefill ?? 'fresh'}'),
            sessionKind: CaptureSessionKind.fotoZen,
            context: context,
          ),
          settings: RouteSettings(
            name: '${AppConstants.kRouteCapture}-ai',
            arguments: prefill == null ? null : <String, Object?>{'photo': prefill},
          ),
        );
      }
    } else if (mounted && _viewModel.hasError) {
      AppSnackBar.showError(
        context,
        _viewModel.errorMessage ?? 'Failed to accept terms',
      );
    }
  }

  void _openFullTerms() {
    showWebViewUrlSheet(
      context,
      url: AppConstants.kTermsAndConditionsUrl,
      flutterAssetPath: AppConstants.kTermsAndConditionsAssetPath,
    );
  }

  Future<void> _openKioskManagement(BuildContext context) async {
    await Navigator.of(context).pushNamed(
      AppConstants.kRouteSplash,
      arguments: const SplashRouteArgs(manageKiosk: true),
    );
    if (!mounted) return;
    await _viewModel.reloadKioskFromStorage();
  }

  @override
  Widget build(BuildContext context) {
    final rawArgs = ModalRoute.of(context)?.settings.arguments;
    if (_capturePrefillPhoto == null && rawArgs is TermsRouteArgs) {
      _capturePrefillPhoto = rawArgs.capturePhoto;
    }
    // Must run in this State's build — not inside Consumer (State.context is idle then).
    final photoUploadAllowed = context.select<AppSettingsManager, bool>(
      (m) => m.settings?.photoUploadAllowed == true,
    );
    final appColors = AppColors.of(context);
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    
    final layout = TermsLayoutMetrics(
      screenWidth: screenWidth,
      isLandscape: isLandscape,
    );
    final double horizontalPadding = screenWidth * 0.06;
    final double cardMaxWidth = layout.cardMaxWidth;
    final double scrollVerticalPadding = layout.scrollVerticalPadding;

    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Scaffold(
        backgroundColor: appColors.backgroundColor,
        body: SafeArea(
          child: Stack(
            children: [
              // Animated slideshow (theme samples when provided, else default assets)
              Positioned.fill(
                child: AnimatedSlideshowBackground(
                  assetPaths: widget.backgroundImageUrls,
                ),
              ),
              // Main content (no top logo; card has logo in header)
              Column(
                children: [
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                          vertical: scrollVerticalPadding,
                        ),
                        child: Consumer<TermsAndConditionsViewModel>(
                          builder: (context, viewModel, child) {
                            // Gate the whole flow until the kiosk is provisioned.
                            final kioskCode = (viewModel.kioskCode ?? '').trim();
                            if (!viewModel.kioskCodeLoaded) {
                              return ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: cardMaxWidth),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: appColors.primaryColor,
                                  ),
                                ),
                              );
                            }
                            if (kioskCode.isEmpty) {
                              _redirectToSplashForKioskSetup();
                              return ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: cardMaxWidth),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: appColors.primaryColor,
                                  ),
                                ),
                              );
                            }
                            return ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: cardMaxWidth),
                              child: _buildConsentCard(
                                viewModel,
                                appColors,
                                compact: isLandscape,
                                photoUploadAllowed: photoUploadAllowed,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              // Session API overlay only — camera is prepared on Terms before Continue.
              Consumer<TermsAndConditionsViewModel>(
                builder: (context, viewModel, child) {
                  if (!viewModel.isSubmitting && !_startingExperience) {
                    return const SizedBox.shrink();
                  }
                  return Positioned.fill(
                    child: FullScreenLoader(
                      text: _termsStartOverlayText(viewModel.isSubmitting),
                      loaderColor: Colors.blue,
                      elapsedSeconds: viewModel.elapsedSeconds,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConsentCard(
    TermsAndConditionsViewModel viewModel,
    AppColors appColors, {
    bool compact = false,
    required bool photoUploadAllowed,
  }) {
    final layout = TermsLayoutMetrics(
      screenWidth: MediaQuery.sizeOf(context).width,
      isLandscape: compact,
    );
    final cardPadding = layout.cardPadding(compact: compact);
    return Container(
      decoration: BoxDecoration(
        color: appColors.cardBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: appColors.shadowColor.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Fotozen AI logo left of "Quick Consent"
          Padding(
            padding: EdgeInsets.all(cardPadding),
            child: Row(
              children: [
                SizedBox(
                  width: 132,
                  height: 40,
                  child: Image.asset(
                    AppConstants.kBrandLogoAsset,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                    errorBuilder: (_, __, ___) => Icon(
                      CupertinoIcons.photo,
                      size: 40,
                      color: appColors.textColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Terms',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: appColors.textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => _openKioskManagement(context),
                  child: Icon(
                    CupertinoIcons.gear_alt_fill,
                    color: appColors.textColor.withValues(alpha: 0.9),
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
          
          // Divider
          Divider(height: 1, color: appColors.dividerColor),

          _buildCameraPrimingBanner(
            appColors,
            layout,
            compact: compact,
            photoUploadAllowed: photoUploadAllowed,
          ),

          // Content
          Padding(
            padding: EdgeInsets.all(cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildQuickConsentContent(appColors),
              ],
            ),
          ),
          
          // Checkbox section
          Container(
            margin: EdgeInsets.symmetric(horizontal: cardPadding),
            padding: EdgeInsets.all(layout.checkboxAreaPadding(compact: compact)),
            decoration: BoxDecoration(
              color: appColors.backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _buildCheckbox(viewModel, appColors),
          ),
          
          SizedBox(height: layout.sectionGap(compact: compact)),

          if (viewModel.hasError) ...[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: cardPadding),
              child: Text(
                viewModel.errorMessage!,
                style: const TextStyle(
                  color: CupertinoColors.systemRed,
                  fontSize: 14,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: layout.innerSectionGap(compact: compact)),
          ],
          
          // Action button
          Padding(
            padding: EdgeInsets.symmetric(horizontal: cardPadding),
            child: _buildActionButtons(
              viewModel,
              appColors,
              photoUploadAllowed: photoUploadAllowed,
            ),
          ),
          
          SizedBox(height: layout.innerSectionGap(compact: compact)),
          
          // View full T&C link
          Center(
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              onPressed: _openFullTerms,
              child: const Text(
                'View Full Terms & Conditions',
                style: TextStyle(
                  fontSize: 14,
                  color: CupertinoColors.systemBlue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _termsDetectingCamerasMessage() {
    if (!mounted) return AppStrings.termsDetectingCameras;
    final settings = context.read<AppSettingsManager>().settings;
    if (isOnDeviceCanonUsbBooth(settings)) {
      return AppStrings.termsDetectingCamerasCanonUsb;
    }
    return AppStrings.termsDetectingCameras;
  }

  Widget _buildCameraPrimingBanner(
    AppColors appColors,
    TermsLayoutMetrics layout, {
    bool compact = false,
    required bool photoUploadAllowed,
  }) {
    final uploadOk = photoUploadAllowed;
    switch (_cameraPrimingPhase) {
      case TermsCameraPrimingPhase.skipped:
      case TermsCameraPrimingPhase.ready:
        return const SizedBox.shrink();
      case TermsCameraPrimingPhase.detecting:
        return _buildCameraPrimingStatusRow(
          appColors: appColors,
          layout: layout,
          compact: compact,
          message: _termsDetectingCamerasMessage(),
          showSpinner: true,
        );
      case TermsCameraPrimingPhase.permissionDenied:
        return _buildCameraPrimingStatusRow(
          appColors: appColors,
          layout: layout,
          compact: compact,
          message: uploadOk
              ? AppStrings.termsCameraPermissionDeniedUploadOk
              : AppStrings.termsCameraPermissionDenied,
          showRetry: true,
        );
      case TermsCameraPrimingPhase.noneFound:
        return _buildCameraPrimingStatusRow(
          appColors: appColors,
          layout: layout,
          compact: compact,
          message: uploadOk
              ? AppStrings.termsNoCameraDetectedUploadOk
              : AppStrings.termsNoCameraDetected,
          showRetry: true,
        );
      case TermsCameraPrimingPhase.failed:
        return _buildCameraPrimingStatusRow(
          appColors: appColors,
          layout: layout,
          compact: compact,
          message: uploadOk
              ? AppStrings.termsCameraDetectionFailedUploadOk
              : AppStrings.termsCameraDetectionFailed,
          showRetry: true,
        );
    }
  }

  Widget _buildCameraPrimingStatusRow({
    required AppColors appColors,
    required TermsLayoutMetrics layout,
    required String message,
    bool compact = false,
    bool showSpinner = false,
    bool showRetry = false,
  }) {
    final padding = layout.cardPadding(compact: compact);
    return Padding(
      padding: EdgeInsets.fromLTRB(padding, padding, padding, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: appColors.backgroundColor,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showSpinner) ...[
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: CupertinoActivityIndicator(
                  color: appColors.primaryColor,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 13,
                  color: appColors.secondaryTextColor,
                  height: 1.35,
                ),
              ),
            ),
            if (showRetry) ...[
              const SizedBox(width: 8),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: _retryCameraPriming,
                child: Text(
                  AppStrings.termsRetryCameraDetection,
                  style: TextStyle(
                    fontSize: 13,
                    color: appColors.primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQuickConsentContent(AppColors appColors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Review and accept to get started.',
          style: TextStyle(
            fontSize: 15,
            color: appColors.secondaryTextColor,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        _buildBulletPoint('AI processing of your photo to create transformed images', appColors),
        _buildBulletPoint('Automatic deletion of your data 15 minutes after printing', appColors),
        _buildBulletPoint('All people in the photo have given permission to be photographed', appColors),
        const SizedBox(height: 20),
        Text(
          'Your photos are never sold or shared.',
          style: TextStyle(
            fontSize: 14,
            color: appColors.secondaryTextColor,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildBulletPoint(String text, AppColors appColors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(
              fontSize: 15,
              color: appColors.textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: appColors.textColor,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _checkboxBorderColor(bool agreed) {
    if (agreed) return CupertinoColors.systemBlue;
    return CupertinoColors.systemGrey;
  }

  Color _checkboxFillColor(bool agreed) {
    if (agreed) return CupertinoColors.systemBlue;
    return Colors.transparent;
  }

  Color _startButtonLabelColor(bool canSubmit, AppColors appColors) {
    if (canSubmit) return CupertinoColors.white;
    if (appColors.isDarkMode) return CupertinoColors.white;
    return CupertinoColors.black;
  }

  Widget _buildCheckbox(TermsAndConditionsViewModel viewModel, AppColors appColors) {
    final agreed = viewModel.isAgreed;
    return GestureDetector(
      onTap: () => viewModel.toggleAgreement(!agreed),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _checkboxBorderColor(agreed),
                width: 2,
              ),
              color: _checkboxFillColor(agreed),
            ),
            child: agreed
                ? const Icon(
                    CupertinoIcons.checkmark,
                    color: CupertinoColors.white,
                    size: 16,
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'I agree to AI photo processing and confirm everyone has consented',
              style: TextStyle(
                fontSize: 14,
                color: appColors.textColor,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    TermsAndConditionsViewModel viewModel,
    AppColors appColors, {
    required bool photoUploadAllowed,
  }) {
    final canSubmit =
        viewModel.canSubmit && _canStartExperience(photoUploadAllowed);
    final buttonLabel = _cameraPrimingPhase == TermsCameraPrimingPhase.detecting
        ? AppStrings.termsContinueWhenReady
        : 'Start Your Experience';

    return CenteredMaxWidth(
      maxWidth: 360,
      child: SizedBox(
        width: double.infinity,
        child: CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 16),
          color: canSubmit
              ? CupertinoColors.systemBlue
              : CupertinoColors.systemGrey,
          borderRadius: BorderRadius.circular(12),
          onPressed: canSubmit ? _handleAccept : null,
          child: viewModel.isSubmitting || _startingExperience
              ? const CupertinoActivityIndicator(
                  color: CupertinoColors.white,
                )
              : Text(
                  buttonLabel,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _startButtonLabelColor(
                      canSubmit,
                      appColors,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
