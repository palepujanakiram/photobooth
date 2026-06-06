import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings_manager.dart';
import '../../views/widgets/debug_ram_monitor_overlay.dart';
import '../../views/widgets/debug_log_overlay.dart';
import '../../views/widgets/full_screen_loader.dart';
import '../../views/widgets/leading_with_alice.dart';
import '../../views/widgets/theme_background.dart';
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
  });

  final CaptureViewModel viewModel;
  final Widget body;
  final VoidCallback onBack;
  final VoidCallback onSelectCamera;
  final VoidCallback onOpenRotation;
  final VoidCallback onReloadCameras;

  bool get _cameraActionsDisabled =>
      viewModel.isLoadingCameras || viewModel.isInitializing;

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
                top: MediaQuery.paddingOf(context).top + kToolbarHeight + 22 + 6,
              ),
              child: body,
            ),
          ),
          if (viewModel.isUploading)
            Positioned.fill(
              child: FullScreenLoader(
                text: 'Processing Your Photo',
                loaderColor: Colors.blue,
                elapsedSeconds: viewModel.uploadElapsedSeconds,
              ),
            ),
          const _PhotoCaptureDebugOverlays(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      forceMaterialTransparency: true,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
      ),
      title: const Text(
        'POSE',
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
            'Step in front of the camera and strike your best look',
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
        onPressed: onBack,
      ),
      actions: [
        if (viewModel.availableCameras.length > 1)
          IconButton(
            icon: Icon(
              CupertinoIcons.camera_rotate,
              color: _cameraActionsDisabled ? Colors.grey : Colors.white,
            ),
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

class _PhotoCaptureDebugOverlays extends StatelessWidget {
  const _PhotoCaptureDebugOverlays();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppSettingsManager>(
      builder: (context, appSettings, _) {
        if (kIsWeb || appSettings.settings?.showGenerationCommentary != true) {
          return const SizedBox.shrink();
        }
        final top = MediaQuery.paddingOf(context).top + kToolbarHeight + 6;
        return Stack(
          children: [
            Positioned(
              left: 10,
              top: top,
              child: const DebugRamMonitorOverlay(),
            ),
            Positioned(
              left: 10,
              top: top + 52,
              child: const DebugLogOverlay(),
            ),
          ],
        );
      },
    );
  }
}
