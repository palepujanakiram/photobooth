import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/app_strings.dart';
import '../../views/widgets/full_screen_loader.dart';
import '../../views/widgets/leading_with_alice.dart';
import '../../views/widgets/theme_background.dart';
import 'photo_capture_strip_thumbs.dart';
import 'photo_capture_view_layout.dart';
import 'photo_capture_viewmodel.dart';

/// App bar + themed body stack for the capture screen (Sonar S3776 extraction).
class PhotoCaptureScaffold extends StatelessWidget {
  const PhotoCaptureScaffold({
    super.key,
    required this.viewModel,
    required this.body,
    required this.onBack,
    required this.onSelectCamera,
    required this.onOpenRotation,
    required this.onReloadCameras,
    this.subtitleHint,
    this.stripShotFiles = const [],
    this.stripShotTotal,
    this.stripPendingFile,
  });

  final CaptureViewModel viewModel;
  final Widget body;
  final VoidCallback onBack;
  final VoidCallback onSelectCamera;
  final VoidCallback onOpenRotation;
  final VoidCallback onReloadCameras;

  /// Optional POSE subtitle override (e.g. FotoFlashback "Shot 2 of 4").
  final String? subtitleHint;

  /// Accepted FotoFlashback stills (shown in the top thumbnail strip).
  final List<XFile> stripShotFiles;

  /// Total slots for FotoFlashback (e.g. 4). Null hides the strip.
  final int? stripShotTotal;

  /// Current review still before it is accepted into [stripShotFiles].
  final XFile? stripPendingFile;

  bool get _cameraActionsDisabled =>
      viewModel.isLoadingCameras || viewModel.isInitializing;

  bool get _showStrip =>
      stripShotTotal != null &&
      stripShotTotal! > 1 &&
      (stripShotFiles.isNotEmpty || stripPendingFile != null);

  // Subtitle + stamp thumbs (64px) matching 2×6 print cell AR.
  double get _appBarExtraHeight => _showStrip ? 22 + 78 : 22;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(context),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: ThemeBackground(theme: null)),
          SafeArea(
            top: false,
            bottom: false,
            child: Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top +
                    kToolbarHeight +
                    _appBarExtraHeight +
                    6,
                bottom: captureScaffoldBottomInset(
                  paddingBottom: MediaQuery.paddingOf(context).bottom,
                  viewPaddingBottom: MediaQuery.viewPaddingOf(context).bottom,
                  systemGestureInsetBottom:
                      MediaQuery.systemGestureInsetsOf(context).bottom,
                  isAndroid: defaultTargetPlatform == TargetPlatform.android,
                ),
              ),
              child: body,
            ),
          ),
          if (viewModel.isUploading)
            Positioned.fill(
              child: FullScreenLoader(
                text: 'Processing Your Photo',
                loaderColor: Colors.blue,
                autonomousElapsed: true,
                subtitle: viewModel.uploadStatusMessage ?? 'Please wait…',
              ),
            ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final hint = subtitleHint?.trim() ?? '';
    final subtitle = hint.isNotEmpty ? hint : AppStrings.poseSubtitleDefault;
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      forceMaterialTransparency: true,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFF050810),
        systemNavigationBarIconBrightness: Brightness.light,
        systemNavigationBarContrastEnforced: false,
      ),
      title: const Text(
        'POSE',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 22,
        ),
      ),
      bottom: PreferredSize(
        preferredSize: Size.fromHeight(_appBarExtraHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                subtitle,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (_showStrip)
              PhotoCaptureStripThumbs(
                shotFiles: stripShotFiles,
                total: stripShotTotal!,
                pendingFile: stripPendingFile,
              ),
          ],
        ),
      ),
      leading: IconButton(
        icon: const Icon(CupertinoIcons.back, color: Colors.white),
        onPressed: onBack,
      ),
      actions: [
        IconButton(
          icon: Icon(
            CupertinoIcons.camera_rotate,
            color: _cameraActionsDisabled ? Colors.grey : Colors.white,
          ),
          tooltip: 'Select camera',
          onPressed: _cameraActionsDisabled ? null : onSelectCamera,
        ),
        IconButton(
          icon: Icon(
            CupertinoIcons.rotate_right,
            color: _cameraActionsDisabled ? Colors.grey : Colors.white,
          ),
          onPressed: _cameraActionsDisabled ? null : onOpenRotation,
        ),
        IconButton(
          icon: Icon(
            CupertinoIcons.arrow_clockwise,
            color: _cameraActionsDisabled ? Colors.grey : Colors.white,
          ),
          onPressed: _cameraActionsDisabled ? null : onReloadCameras,
        ),
        const AppBarAliceAction(),
      ],
    );
  }
}
