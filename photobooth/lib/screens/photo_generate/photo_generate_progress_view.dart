import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings_manager.dart';
import '../../services/theme_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/route_args.dart';
import '../../views/widgets/ambient_nebula_overlay.dart';
import '../../views/widgets/theme_background.dart';
import 'generation_reveal_overlay.dart';
import 'generation_wait_widgets.dart';
import 'photo_generate_viewmodel.dart';

class PhotoGenerateProgressScreen extends StatefulWidget {
  const PhotoGenerateProgressScreen({super.key});

  @override
  State<PhotoGenerateProgressScreen> createState() =>
      _PhotoGenerateProgressScreenState();
}

class _PhotoGenerateProgressScreenState
    extends State<PhotoGenerateProgressScreen> {
  PhotoGenerateViewModel? _vm;
  int? _lastRunToken;
  bool _navigatedToResult = false;
  bool _generationScheduled = false;
  bool _showRevealOverlay = false;
  bool _revealScheduled = false;
  String? _revealImageUrl;
  String _revealThemeName = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final parsed =
        GenerateArgs.tryParse(ModalRoute.of(context)?.settings.arguments);
    if (parsed == null) return;
    if (parsed.runToken == _lastRunToken) return;

    _lastRunToken = parsed.runToken;
    _navigatedToResult = false;
    _generationScheduled = false;
    _showRevealOverlay = false;
    _revealScheduled = false;
    _revealImageUrl = null;
    _revealThemeName = '';

    if (_vm != null && !_navigatedToResult) {
      _detachRevealListener(_vm);
      _vm!.cancelOperation();
      _vm!.dispose();
    }
    _vm = PhotoGenerateViewModel(
      appSettingsManager: context.read<AppSettingsManager>(),
    );
    unawaited(ThemeManager().fetchThemes());
    unawaited(_vm!.loadProgressiveDisplayPreference());
    _vm!.initialize(parsed.photo, parsed.theme);
    _attachRevealListener(_vm!);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleGeneration(parsed.runToken);
    });
  }

  void _attachRevealListener(PhotoGenerateViewModel vm) {
    vm.addListener(_onGenerationViewModelUpdate);
  }

  void _detachRevealListener(PhotoGenerateViewModel? vm) {
    vm?.removeListener(_onGenerationViewModelUpdate);
  }

  void _onGenerationViewModelUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _vm == null) return;
      _maybeStartReveal(_vm!);
    });
  }

  void _scheduleGeneration(int runToken) {
    if (!mounted || _vm == null || _lastRunToken != runToken) return;
    if (_generationScheduled) return;
    _generationScheduled = true;
    unawaited(_vm!.generateImage());
  }

  @override
  void dispose() {
    _detachRevealListener(_vm);
    if (!_navigatedToResult) {
      _vm?.dispose();
    }
    super.dispose();
  }

  void _maybeStartReveal(PhotoGenerateViewModel vm) {
    if (_navigatedToResult || _showRevealOverlay || _revealScheduled) return;
    final done = vm.generatedImages.isNotEmpty && !vm.isOperationInProgress;
    if (!done) return;
    _revealScheduled = true;
    if (vm.hasError) {
      vm.clearError();
    }
    final image = vm.generatedImages.first;
    setState(() {
      _showRevealOverlay = true;
      _revealImageUrl = image.imageUrl;
      _revealThemeName = image.theme.name;
    });
  }

  void _finishRevealAndNavigate(BuildContext context, PhotoGenerateViewModel vm) {
    if (_navigatedToResult) return;
    _navigatedToResult = true;
    vm.markBeholdEntranceFromProgressReveal();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AppConstants.kRouteGenerate,
        arguments: vm,
      );
    });
  }

  PreferredSizeWidget _buildAppBar(PhotoGenerateViewModel viewModel) {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      forceMaterialTransparency: true,
      centerTitle: true,
      title: const Text(
        AppStrings.generationProgressTitle,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 22,
        ),
      ),
      automaticallyImplyLeading: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = _vm;
    if (vm == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final size = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final cardW = size.width;
    final cardH = math.max(360.0, size.height - topInset);

    return ChangeNotifierProvider.value(
      value: vm,
      child: Consumer<PhotoGenerateViewModel>(
        builder: (context, viewModel, _) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: _buildAppBar(viewModel),
            body: Stack(
              children: [
                Positioned.fill(
                  child: ThemeBackground(theme: viewModel.selectedTheme),
                ),
                const Positioned.fill(child: AmbientNebulaOverlay()),
                SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      SizedBox(
                        height: MediaQuery.paddingOf(context).top +
                            kToolbarHeight,
                      ),
                      Expanded(
                        child: GenerationWaitBody(
                          viewModel: viewModel,
                          cardWidth: cardW,
                          cardHeight: cardH,
                          useKioskLayout: true,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_showRevealOverlay && (_revealImageUrl ?? '').isNotEmpty)
                  Positioned.fill(
                    child: GenerationRevealOverlay(
                      imageUrl: _revealImageUrl!,
                      themeName: _revealThemeName,
                      onComplete: () =>
                          _finishRevealAndNavigate(context, viewModel),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
