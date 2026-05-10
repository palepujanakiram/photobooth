import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart'
    show CupertinoColors, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_settings_manager.dart';
import '../../views/widgets/theme_background.dart';
import '../../utils/constants.dart';
import '../../utils/route_args.dart';
import '../../utils/secure_image_url.dart';
import '../../utils/transformation_step_display.dart';
import '../../views/widgets/cached_network_image.dart';
import '../photo_capture/photo_image_from_xfile_io.dart'
    if (dart.library.html) '../photo_capture/photo_image_from_xfile_web.dart'
    as photo_image;
import 'photo_generate_viewmodel.dart';

class PhotoGenerateProgressScreen extends StatefulWidget {
  const PhotoGenerateProgressScreen({super.key});

  @override
  State<PhotoGenerateProgressScreen> createState() =>
      _PhotoGenerateProgressScreenState();
}

class _PhotoGenerateProgressScreenState
    extends State<PhotoGenerateProgressScreen> {
  late PhotoGenerateViewModel _vm;
  bool _vmCreated = false;
  bool _initialized = false;
  bool _navigatedToResult = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_vmCreated) {
      _vm = PhotoGenerateViewModel(
        appSettingsManager: context.read<AppSettingsManager>(),
      );
      _vmCreated = true;
      unawaited(_vm.loadProgressiveDisplayPreference());
    }
    if (!_initialized) {
      _initializeFromArgsAndStart();
      _initialized = true;
    }
  }

  void _initializeFromArgsAndStart() {
    final parsed =
        GenerateArgs.tryParse(ModalRoute.of(context)?.settings.arguments);
    if (parsed == null) return;
    _vm.initialize(parsed.photo, parsed.theme);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _vm.generateImage();
    });
  }

  @override
  void dispose() {
    // If we handed the ViewModel off to `/generate`, it becomes owned there.
    if (!_navigatedToResult) {
      _vm.dispose();
    }
    super.dispose();
  }

  void _maybeNavigateToResult(BuildContext context, PhotoGenerateViewModel vm) {
    if (_navigatedToResult) return;
    final done = vm.generatedImages.isNotEmpty && !vm.isOperationInProgress;
    if (!done) return;
    _navigatedToResult = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AppConstants.kRouteGenerate,
        // Hand off the same VM so selection/continue/payment flow is unchanged.
        arguments: vm,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final aspect = 3 / 2;

    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<PhotoGenerateViewModel>(
        builder: (context, vm, _) {
          _maybeNavigateToResult(context, vm);

          final maxW = size.width;
          // Keep consistent with BEHOLD hero card sizing.
          final maxH = math.min(size.height * 0.72, 980.0);
          double cardW;
          double cardH;
          if (maxW / maxH > aspect) {
            cardH = maxH;
            cardW = cardH * aspect;
          } else {
            cardW = maxW;
            cardH = cardW / aspect;
          }

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
              leading: IconButton(
                icon: const Icon(CupertinoIcons.back, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            body: Stack(
              children: [
                Positioned.fill(child: ThemeBackground(theme: vm.selectedTheme)),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + kToolbarHeight),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight - 24,
                            ),
                            child: Center(
                              child: _buildGenerationProgressHeroCard(
                                context,
                                vm,
                                width: cardW,
                                height: cardH,
                              ),
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

  Widget _transformedSlotFrame({
    required double cardWidth,
    required double cardHeight,
    required Widget child,
  }) {
    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: child,
        ),
      ),
    );
  }

  Widget _buildGenerationProgressHeroCard(
    BuildContext context,
    PhotoGenerateViewModel vm, {
    required double width,
    required double height,
  }) {
    final preprocessUrl = _previewForStage(vm, 'preprocessing');
    final bgUrl = _previewForStage(vm, 'background_removal');
    final aiUrl = _previewForStage(vm, 'ai_generation');

    int index = 0;
    String stageTitle = '2 · CAPTURE';
    String headline = 'Got it';
    String description = 'Frozen frame, framing applied';
    String? imageUrl;
    bool checker = false;
    Widget? localFallback;
    Widget? bottomAccessory;

    if (vm.originalPhoto != null) {
      localFallback = photo_image.imageFromXFileSized(
        vm.originalPhoto!.imageFile,
        1280,
        1280,
        fit: BoxFit.contain,
      );
    }

    if (aiUrl != null) {
      index = 3;
      stageTitle = '4 · REVEAL';
      headline = 'Rendering';
      description = 'AI is applying your style';
      imageUrl = aiUrl;
      bottomAccessory = _buildPostRevealPolishingOverlay(context, vm);
    } else if (bgUrl != null) {
      index = 2;
      stageTitle = '3 · ISOLATE';
      headline = 'Background removed';
      description = 'Subject isolated, ready to render';
      imageUrl = bgUrl;
      checker = true;
    } else if (preprocessUrl != null) {
      index = 1;
      stageTitle = '2 · CAPTURE';
      headline = 'Got it';
      description = 'Frozen frame, framing applied';
      imageUrl = preprocessUrl;
    } else {
      index = 0;
      stageTitle = '1 · DETECT';
      headline = 'Face locked';
      description = 'Live preview';
    }

    Widget imageLayer() {
      if (imageUrl != null) {
        return CachedNetworkImage(
          imageUrl: SecureImageUrl.withSessionId(imageUrl),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          placeholder: localFallback ??
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
          errorWidget: localFallback,
        );
      }
      return localFallback ?? const SizedBox.shrink();
    }

    // Match PhotoGenerateScreen: photo frame is image-only; status lives outside.
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  stageTitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                  textAlign: TextAlign.left,
                ),
                const SizedBox(height: 8),
                _storyboardTopBars(activeIndex: index),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: width,
            height: height,
            child: _transformedSlotFrame(
              cardWidth: width,
              cardHeight: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (checker)
                    _checkerboardBackground()
                  else
                    const ColoredBox(color: Colors.black),
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeOutCubic,
                      transitionBuilder: (child, anim) {
                        final fade = CurvedAnimation(
                          parent: anim,
                          curve: Curves.easeOut,
                        );
                        final scale =
                            Tween<double>(begin: 0.985, end: 1.0).animate(fade);
                        return FadeTransition(
                          opacity: fade,
                          child: ScaleTransition(scale: scale, child: child),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey<String>(imageUrl ?? 'local_$index'),
                        child: imageLayer(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  headline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  '${vm.elapsedSeconds}s',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (bottomAccessory != null) ...[
                  const SizedBox(height: 12),
                  bottomAccessory,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _previewForStage(PhotoGenerateViewModel vm, String stageKey) {
    final want = stageKey.trim().toLowerCase();
    for (final s in vm.generationRunStepPreviews) {
      final key = canonicalPipelineStageKey(s.stage);
      if (key == want && (s.previewUrl ?? '').trim().isNotEmpty) {
        return s.previewUrl!.trim();
      }
    }
    return null;
  }

  Widget _buildPostRevealPolishingOverlay(
    BuildContext context,
    PhotoGenerateViewModel vm,
  ) {
    final steps = vm.generationRunStepPreviews;
    if (steps.isEmpty) return const SizedBox.shrink();

    final byStage = <String, GenerationRunStepPreview>{};
    for (final s in steps) {
      byStage[canonicalPipelineStageKey(s.stage)] = s;
    }

    const polishOrder = <String>[
      'scene_lighting',
      'face_relight',
      'frame_composite',
      'upscaling',
      'exif_stamp',
      'c2pa_sign',
      'storage',
    ];

    String? activeKey;
    for (final k in polishOrder) {
      final s = byStage[k];
      if (s != null && s.isActive) {
        activeKey = k;
        break;
      }
    }
    activeKey ??= byStage['storage']?.isFinished == true
        ? 'storage'
        : (polishOrder.firstWhere(
            (k) => byStage[k]?.isFinished != true,
            orElse: () => 'storage',
          ));

    String copyFor(String k) {
      switch (k) {
        case 'scene_lighting':
          return 'Matching scene lighting';
        case 'face_relight':
          return 'Relighting your face';
        case 'frame_composite':
          return 'Adding your frame';
        case 'upscaling':
          return 'Sharpening for print';
        case 'exif_stamp':
          return 'Branding';
        case 'c2pa_sign':
          return 'Signing authenticity';
        case 'storage':
          return 'Preparing print file';
        default:
          return transformationStepDisplayLabel(k);
      }
    }

    Widget stageChip(String k) {
      final s = byStage[k];
      final finished = s?.isFinished == true;
      final active = s?.isActive == true;
      final color = active
          ? CupertinoColors.activeBlue
          : finished
              ? Colors.lightGreenAccent.withValues(alpha: 0.9)
              : Colors.white30;
      final icon = finished
          ? Icons.check_circle
          : active
              ? Icons.autorenew
              : Icons.more_horiz;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.85), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              copyFor(k),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(CupertinoIcons.wand_stars,
                      color: Colors.white70, size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Finishing touches · ${copyFor(activeKey)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < polishOrder.length; i++) ...[
                      if (i != 0) const SizedBox(width: 8),
                      stageChip(polishOrder[i]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _storyboardTopBars({required int activeIndex}) {
    const total = 4;
    return SizedBox(
      height: 10,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < total; i++) ...[
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: i == activeIndex ? 42 : 22,
              height: 6,
              decoration: BoxDecoration(
                color: i <= activeIndex
                    ? CupertinoColors.systemBlue
                    : Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            if (i != total - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

  Widget _checkerboardBackground() {
    return CustomPaint(
      painter: _CheckerPainter(),
      child: const SizedBox.expand(),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 22.0;
    final paintA = Paint()..color = const Color(0xFF2A2A2A);
    final paintB = Paint()..color = const Color(0xFF1E1E1E);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final isA = ((x / cell).floor() + (y / cell).floor()) % 2 == 0;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), isA ? paintA : paintB);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

