import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_settings_manager.dart';
import '../../services/theme_manager.dart';
import '../../views/widgets/theme_background.dart';
import '../../utils/constants.dart';
import '../../utils/route_args.dart';
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

    if (_vm != null && !_navigatedToResult) {
      _vm!.cancelOperation();
      _vm!.dispose();
    }
    _vm = PhotoGenerateViewModel(
      appSettingsManager: context.read<AppSettingsManager>(),
    );
    unawaited(ThemeManager().fetchThemes());
    unawaited(_vm!.loadProgressiveDisplayPreference());
    _vm!.initialize(parsed.photo, parsed.theme);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleGeneration(parsed.runToken);
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
    if (!_navigatedToResult) {
      _vm?.dispose();
    }
    super.dispose();
  }

  void _maybeNavigateToResult(BuildContext context, PhotoGenerateViewModel vm) {
    if (_navigatedToResult) return;
    final done = vm.generatedImages.isNotEmpty && !vm.isOperationInProgress;
    if (!done) return;
    if (vm.hasError) {
      vm.clearError();
    }
    _navigatedToResult = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AppConstants.kRouteGenerate,
        arguments: vm,
      );
    });
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
    const aspect = 3 / 2;
    final maxW = size.width;
    final maxH = math.min(size.height * 0.72, 980.0);
    final double cardW;
    final double cardH;
    if (maxW / maxH > aspect) {
      cardH = maxH;
      cardW = cardH * aspect;
    } else {
      cardW = maxW;
      cardH = cardW / aspect;
    }

    return ChangeNotifierProvider.value(
      value: vm,
      child: Consumer<PhotoGenerateViewModel>(
        builder: (context, viewModel, _) {
          _maybeNavigateToResult(context, viewModel);

          return Scaffold(
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
                'BEHOLD',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 22,
                ),
              ),
              automaticallyImplyLeading: false,
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: ThemeBackground(theme: viewModel.selectedTheme),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top + kToolbarHeight,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: GenerationWaitBody(
                              viewModel: viewModel,
                              cardWidth: cardW,
                              cardHeight: cardH,
                            ),
                          ),
                        );
                      },
                    ),
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
