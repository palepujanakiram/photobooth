import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/customer_session_lifecycle.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/secure_image_url.dart';
import '../../utils/transformation_step_display.dart';
import '../../views/widgets/cached_network_image.dart';
import '../../views/widgets/kiosk_vertical_screen_layout.dart';
import '../theme_selection/theme_preview_screen.dart';
import '../photo_capture/photo_image_from_xfile_io.dart'
    if (dart.library.html) '../photo_capture/photo_image_from_xfile_web.dart'
    as photo_image;
import 'generation_wait_helpers.dart';
import 'generation_wait_story_helpers.dart';
import 'generation_wait_phase2_widgets.dart';
import 'generation_wait_theme_reel.dart';
import 'generation_wait_eta_widgets.dart';
import 'photo_generate_viewmodel.dart';
import 'post_reveal_polishing_overlay.dart';

/// Slow zoom/pan on the capture still so the wait state feels alive.
class KenBurnsCaptureImage extends StatefulWidget {
  const KenBurnsCaptureImage({
    super.key,
    required this.imageFile,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
    this.alignment = kGenerationWaitPortraitFaceAlignment,
  });

  final XFile imageFile;
  final double width;
  final double height;
  final BoxFit fit;
  final Alignment alignment;

  @override
  State<KenBurnsCaptureImage> createState() => _KenBurnsCaptureImageState();
}

class _KenBurnsCaptureImageState extends State<KenBurnsCaptureImage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_controller.value);
        final scale = 1.0 + t * 0.07;
        final align = Alignment(
          -0.03 + t * 0.06,
          -0.02 + t * 0.04,
        );
        return Transform.scale(
          scale: scale,
          alignment: align,
          child: child,
        );
      },
      child: photo_image.imageFromXFileSized(
        widget.imageFile,
        widget.width,
        widget.height,
        fit: widget.fit,
        alignment: widget.alignment,
      ),
    );
  }
}

/// Before / after anticipation frame before server previews arrive.
class ThemeAnticipationHero extends StatelessWidget {
  const ThemeAnticipationHero({
    super.key,
    required this.viewModel,
    required this.width,
    required this.height,
  });

  final PhotoGenerateViewModel viewModel;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = viewModel.selectedTheme;
    final photo = viewModel.originalPhoto;
    final captureAlignment =
        generationWaitCaptureImageAlignment(viewModel.sessionPersonCount);
    final sampleUrl = theme == null
        ? ''
        : ThemePreviewScreen.resolveSampleImageUrl(theme);
    final gap = width > 520 ? 10.0 : 8.0;
    final cellW = (width - gap) / 2;
    final imageH = math.max(80.0, height - kGenerationWaitAnticipationLabelOverhead);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          height: height,
          child: Row(
            children: [
              Expanded(
                child: _labeledCell(
                  label: AppStrings.generationWaitBeforeLabel,
                  child: photo != null
                      ? KenBurnsCaptureImage(
                          imageFile: photo.imageFile,
                          width: cellW,
                          height: imageH,
                          alignment: captureAlignment,
                        )
                      : const ColoredBox(color: Colors.black),
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                child: _labeledCell(
                  label: AppStrings.generationWaitAfterLabel,
                  child: _afterCell(
                    sampleUrl,
                    cellW,
                    imageH,
                    alignment: captureAlignment,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _labeledCell({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          ),
        ),
      ],
    );
  }

  Widget _afterCell(
    String sampleUrl,
    double cellW,
    double height, {
    required Alignment alignment,
  }) {
    if (sampleUrl.isEmpty) {
      return const _ShimmerPlaceholder();
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          alignment: alignment,
          child: CachedNetworkImage(
            imageUrl: sampleUrl,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
            errorWidget: const _ShimmerPlaceholder(),
          ),
        ),
        Container(
          color: Colors.black.withValues(alpha: 0.28),
          child: const Center(
            child: Icon(
              CupertinoIcons.sparkles,
              color: Colors.white70,
              size: 36,
            ),
          ),
        ),
      ],
    );
  }
}

class _ShimmerPlaceholder extends StatefulWidget {
  const _ShimmerPlaceholder();

  @override
  State<_ShimmerPlaceholder> createState() => _ShimmerPlaceholderState();
}

class _ShimmerPlaceholderState extends State<_ShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.06 + _pulse.value * 0.08),
                Colors.white.withValues(alpha: 0.14 + _pulse.value * 0.1),
              ],
            ),
          ),
          child: const Center(
            child: Icon(
              CupertinoIcons.sparkles,
              color: Colors.white38,
              size: 32,
            ),
          ),
        );
      },
    );
  }
}

class GenerationStoryboardBars extends StatelessWidget {
  const GenerationStoryboardBars({
    super.key,
    required this.activeIndex,
    required this.progress,
  });

  final int activeIndex;
  final double progress;

  @override
  Widget build(BuildContext context) {
    const total = 4;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
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
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: Colors.white24,
            color: CupertinoColors.systemBlue,
          ),
        ),
      ],
    );
  }
}

class GenerationPipelineStoryCard extends StatelessWidget {
  const GenerationPipelineStoryCard({
    super.key,
    required this.viewModel,
    required this.commentaryEnabled,
    this.onStampTap,
    this.maxWidth = 560,
  });

  final PhotoGenerateViewModel viewModel;
  final bool commentaryEnabled;
  final void Function(int index)? onStampTap;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final slots = viewModel.pipelineFunnelSlots;
    if (slots.isEmpty) return const SizedBox.shrink();

    final progress = generationWaitEffectiveProgress(
      pipelineProgress: viewModel.pipelineFunnelProgress,
      elapsedSeconds: viewModel.elapsedSeconds,
      hasServerPreviews: viewModel.generationRunStepPreviews.isNotEmpty,
    );
    final line = generationWaitCommentaryLine(
          viewModel,
          commentaryEnabled: commentaryEnabled,
        ) ??
        (viewModel.progressMessage.isNotEmpty
            ? viewModel.progressMessage
            : generationWaitRotatingCopy(viewModel.elapsedSeconds));

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Card(
        elevation: 10,
        shadowColor: CupertinoColors.systemBlue.withValues(alpha: 0.22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF4A4A4A), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.black.withValues(alpha: 0.78),
                Colors.black.withValues(alpha: 0.52),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      CupertinoIcons.sparkles,
                      color: Colors.white70,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'AI generation',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      '${(progress * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 68,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: slots.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => GenerationFunnelStamp(
                      viewModel: viewModel,
                      slot: slots[i],
                      index: i,
                      onTap: onStampTap == null ? null : () => onStampTap!(i),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 10,
                    backgroundColor: Colors.white24,
                    color: CupertinoColors.systemBlue,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  line,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class GenerationFunnelStamp extends StatelessWidget {
  const GenerationFunnelStamp({
    super.key,
    required this.viewModel,
    required this.slot,
    required this.index,
    this.onTap,
  });

  final PhotoGenerateViewModel viewModel;
  final PipelineFunnelSlot slot;
  final int index;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const thumb = 60.0;
    const outer = 68.0;
    final url = slot.displayPreviewUrl;
    final status = _slotStatusLabel(slot);

    late final Widget inner;
    if (slot.isDeviceCapture) {
      final photo = viewModel.originalPhoto;
      inner = photo != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: thumb,
                height: thumb,
                child: photo_image.imageFromXFileSized(
                  photo.imageFile,
                  thumb,
                  thumb,
                  fit: BoxFit.cover,
                ),
              ),
            )
          : Icon(
              transformationStepIcon(slot.stageKey),
              color: Colors.white54,
              size: 32,
            );
    } else if (url != null && url.isNotEmpty) {
      inner = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: SecureImageUrl.withSessionId(url),
          width: thumb,
          height: thumb,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
        ),
      );
    } else if (slot.isFinished) {
      inner = const Icon(
        Icons.check_circle,
        color: Colors.lightGreenAccent,
        size: 32,
      );
    } else if (slot.isActive) {
      inner = const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
      );
    } else {
      inner = Icon(
        Icons.image_outlined,
        color: Colors.white.withValues(alpha: 0.35),
        size: 32,
      );
    }

    final borderColor = slot.isActive
        ? CupertinoColors.systemBlue
        : slot.isFinished
            ? Colors.lightGreenAccent.withValues(alpha: 0.75)
            : Colors.white24;

    return Tooltip(
      message: '${slot.label} — $status',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: outer,
            height: outer,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: Center(child: inner),
          ),
        ),
      ),
    );
  }

  static String _slotStatusLabel(PipelineFunnelSlot slot) {
    if (slot.isFinished) return 'Done';
    if (slot.isActive) return 'In progress';
    return 'Queued';
  }
}

class GenerationWaitHeroCard extends StatelessWidget {
  const GenerationWaitHeroCard({
    super.key,
    required this.viewModel,
    required this.presentation,
    required this.width,
    required this.height,
  });

  final PhotoGenerateViewModel viewModel;
  final GenerationWaitPresentation presentation;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final progress = generationWaitEffectiveProgress(
      pipelineProgress: viewModel.pipelineFunnelProgress,
      elapsedSeconds: viewModel.elapsedSeconds,
      hasServerPreviews: viewModel.generationRunStepPreviews.isNotEmpty,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  presentation.stageTitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                GenerationStoryboardBars(
                  activeIndex: presentation.storyboardIndex,
                  progress: progress,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: width,
            height: height,
            child: _heroFrame(
              context,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 280),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeOutCubic,
                      transitionBuilder: (child, anim) {
                        final fade = CurvedAnimation(
                          parent: anim,
                          curve: Curves.easeOut,
                        );
                        final scale = Tween<double>(begin: 0.985, end: 1.0)
                            .animate(fade);
                        return FadeTransition(
                          opacity: fade,
                          child: ScaleTransition(scale: scale, child: child),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey<String>(
                          presentation.imageUrl ?? 'anticipation',
                        ),
                        child: _heroImage(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          _statusBlock(presentation),
          if (presentation.showPolishingOverlay) ...[
            const SizedBox(height: 12),
            PostRevealPolishingOverlay(
              steps: viewModel.generationRunStepPreviews,
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroFrame(BuildContext context, {required Widget child}) {
    return DecoratedBox(
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
    );
  }

  Widget _heroImage(BuildContext context) {
    final imageUrl = presentation.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return _networkStageImage(context, imageUrl);
    }
    return ThemeAnticipationHero(
      viewModel: viewModel,
      width: width,
      height: height,
    );
  }

  Widget _networkStageImage(BuildContext context, String imageUrl) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheW = (width * dpr).ceil().clamp(64, 2048);
    final captureAlignment =
        generationWaitCaptureImageAlignment(viewModel.sessionPersonCount);
    const loading = Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2,
        ),
      ),
    );
    final fallback = viewModel.originalPhoto != null
        ? KenBurnsCaptureImage(
            imageFile: viewModel.originalPhoto!.imageFile,
            width: width,
            height: height,
            alignment: captureAlignment,
          )
        : loading;

    return SizedBox(
      width: width,
      height: height,
      child: ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: captureAlignment,
          child: CachedNetworkImage(
            imageUrl: imageUrl.trim(),
            fit: BoxFit.cover,
            cacheWidth: cacheW,
            filterQuality: FilterQuality.medium,
            placeholder: loading,
            errorWidget: fallback,
          ),
        ),
      ),
    );
  }

  Widget _statusBlock(GenerationWaitPresentation presentation) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        children: [
          Text(
            presentation.headline,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            presentation.description,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.25,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          GenerationWaitEducationalFooter(
            elapsedSeconds: viewModel.elapsedSeconds,
          ),
        ],
      ),
    );
  }
}

/// Large reveal frame during live previews — no pipeline stamps or stage numbers.
class GenerationWaitCinematicHero extends StatelessWidget {
  const GenerationWaitCinematicHero({
    super.key,
    required this.viewModel,
    required this.presentation,
    required this.width,
    required this.height,
    this.showPolishingStripBelow = true,
  });

  final PhotoGenerateViewModel viewModel;
  final GenerationWaitPresentation presentation;
  final double width;
  final double height;

  /// When false, [PostRevealPolishingOverlay] is omitted (kiosk footer owns it).
  final bool showPolishingStripBelow;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 500),
                      switchInCurve: Curves.easeOutCubic,
                      child: KeyedSubtree(
                        key: ValueKey<String>(
                          presentation.imageUrl ?? 'anticipation',
                        ),
                        child: _heroContent(context),
                      ),
                    ),
                  ),
                  if (presentation.showPolishingOverlay)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.35),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (showPolishingStripBelow && presentation.showPolishingOverlay) ...[
          const SizedBox(height: 10),
          PostRevealPolishingOverlay(
            steps: viewModel.generationRunStepPreviews,
          ),
        ],
      ],
    );
  }

  Widget _heroContent(BuildContext context) {
    final imageUrl = presentation.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      return _networkImage(context, imageUrl);
    }
    return ThemeAnticipationHero(
      viewModel: viewModel,
      width: width,
      height: height,
    );
  }

  Widget _networkImage(BuildContext context, String imageUrl) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheW = (width * dpr).ceil().clamp(64, 2048);
    final captureAlignment =
        generationWaitCaptureImageAlignment(viewModel.sessionPersonCount);
    final photo = viewModel.originalPhoto;
    final fallback = photo != null
        ? KenBurnsCaptureImage(
            imageFile: photo.imageFile,
            width: width,
            height: height,
            alignment: captureAlignment,
          )
        : const ColoredBox(color: Colors.black);

    return SizedBox(
      width: width,
      height: height,
      child: FittedBox(
        fit: BoxFit.cover,
        alignment: captureAlignment,
        child: CachedNetworkImage(
          imageUrl: imageUrl.trim(),
          fit: BoxFit.cover,
          cacheWidth: cacheW,
          filterQuality: FilterQuality.medium,
          placeholder: fallback,
          errorWidget: fallback,
        ),
      ),
    );
  }
}

/// Full progress-route body with phased anticipation → pipeline UX.
class GenerationWaitBody extends StatefulWidget {
  const GenerationWaitBody({
    super.key,
    required this.viewModel,
    required this.cardWidth,
    required this.cardHeight,
    this.onStampTap,
    this.useKioskLayout = false,
  });

  final PhotoGenerateViewModel viewModel;
  final double cardWidth;
  final double cardHeight;
  final void Function(int index)? onStampTap;

  /// POSE-style top→bottom zones (progress route). Off when embedded in BEHOLD scroll.
  final bool useKioskLayout;

  @override
  State<GenerationWaitBody> createState() => _GenerationWaitBodyState();
}

class _GenerationWaitBodyState extends State<GenerationWaitBody> {
  GenerationWaitPresentation? _previousPresentation;
  int _lastHapticIndex = -1;

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final presentation = resolveGenerationWaitPresentation(
      vm,
      previous: _previousPresentation,
      commentaryEnabled: vm.generationCommentaryEnabledForWait,
    );

    if (presentation.storyboardIndex > _lastHapticIndex) {
      _lastHapticIndex = presentation.storyboardIndex;
      if (presentation.stageChanged) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          HapticFeedback.lightImpact();
        });
      }
    }
    _previousPresentation = presentation;

    if (vm.hasError && !vm.isOperationInProgress && vm.generatedImages.isEmpty) {
      return _buildErrorState(context, vm);
    }

    final showAnticipation = generationWaitShowAnticipationPhase(vm);

    if (widget.useKioskLayout) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 480),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: showAnticipation
            ? KeyedSubtree(
                key: const ValueKey('anticipation'),
                child: _buildKioskWaitStage(
                  vm,
                  presentation,
                  anticipation: true,
                ),
              )
            : KeyedSubtree(
                key: const ValueKey('reveal'),
                child: _buildKioskWaitStage(
                  vm,
                  presentation,
                  anticipation: false,
                ),
              ),
      );
    }

    final anticipationHeight = widget.cardHeight * 0.72;
    final revealHeight = widget.cardHeight * 0.78;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 480),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: showAnticipation
          ? KeyedSubtree(
              key: const ValueKey('anticipation'),
              child: _buildAnticipationStage(
                vm,
                presentation,
                anticipationHeight,
              ),
            )
          : KeyedSubtree(
              key: const ValueKey('reveal'),
              child: _buildLiveRevealStage(
                vm,
                presentation,
                revealHeight,
              ),
            ),
    );
  }

  Widget _buildKioskWaitStage(
    PhotoGenerateViewModel vm,
    GenerationWaitPresentation presentation, {
    required bool anticipation,
  }) {
    final showFaceScan = generationWaitShowFaceScanChecklist(vm, presentation);
    final faceCount = generationWaitFaceScanCompletedCount(vm.elapsedSeconds);
    final showPolish =
        !anticipation && presentation.showPolishingOverlay;

    return KioskVerticalScreenLayout(
      horizontalPadding: 0,
      heroMaxWidth: 720,
      maxFooterWidth: 720,
      footerScrollable: true,
      maxFooterHeight: showPolish ? 228 : 196,
      chrome: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GenerationWaitPortraitClock(
            snapshot: resolveGenerationEta(vm),
            compact: true,
          ),
          const SizedBox(height: 10),
          GenerationWaitStoryHeader(
            viewModel: vm,
            presentation: presentation,
            compact: true,
            hideRewardWhenPolishing: showPolish,
          ),
        ],
      ),
      hero: LayoutBuilder(
        builder: (context, constraints) {
          final maxW = math.min(widget.cardWidth, constraints.maxWidth);
          final maxH = constraints.maxHeight;
          final cellAspect =
              generationWaitHeroCellAspectRatio(vm.sessionPersonCount);
          final size = anticipation
              ? computeThemeAnticipationHeroSize(
                  maxWidth: maxW,
                  maxHeight: maxH,
                  cellAspect: cellAspect,
                )
              : computeGenerationWaitCinematicHeroSize(
                  maxWidth: maxW,
                  maxHeight: maxH,
                  aspect: cellAspect,
                );

          Widget buildHeroImage(double width, double height) {
            if (anticipation) {
              return ThemeAnticipationHero(
                viewModel: vm,
                width: width,
                height: height,
              );
            }
            return GenerationWaitCinematicHero(
              viewModel: vm,
              presentation: presentation,
              width: width,
              height: height,
              showPolishingStripBelow: false,
            );
          }

          return SizedBox(
            width: size.width,
            height: size.height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                alignment: Alignment.center,
                children: [
                  buildHeroImage(size.width, size.height),
                  if (showFaceScan)
                    GenerationWaitFaceScanOverlay(completedCount: faceCount),
                ],
              ),
            ),
          );
        },
      ),
      footer: _buildWaitStageFooter(
        vm,
        presentation,
        compact: true,
        showPolishStrip: showPolish,
      ),
    );
  }

  Widget _buildLiveRevealStage(
    PhotoGenerateViewModel vm,
    GenerationWaitPresentation presentation,
    double heroHeight,
  ) {
    final cellAspect = generationWaitHeroCellAspectRatio(vm.sessionPersonCount);
    final size = computeGenerationWaitCinematicHeroSize(
      maxWidth: widget.cardWidth,
      maxHeight: heroHeight,
      aspect: cellAspect,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GenerationWaitPortraitClock(snapshot: resolveGenerationEta(vm)),
        const SizedBox(height: 14),
        GenerationWaitStoryHeader(
          viewModel: vm,
          presentation: presentation,
        ),
        const SizedBox(height: 14),
        GenerationWaitCinematicHero(
          viewModel: vm,
          presentation: presentation,
          width: size.width,
          height: size.height,
        ),
        const SizedBox(height: 16),
        _buildWaitStageFooter(vm, presentation),
      ],
    );
  }

  Widget _buildAnticipationStage(
    PhotoGenerateViewModel vm,
    GenerationWaitPresentation presentation,
    double anticipationHeight,
  ) {
    final cellAspect = generationWaitHeroCellAspectRatio(vm.sessionPersonCount);
    final size = computeThemeAnticipationHeroSize(
      maxWidth: widget.cardWidth,
      maxHeight: anticipationHeight,
      cellAspect: cellAspect,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GenerationWaitPortraitClock(snapshot: resolveGenerationEta(vm)),
        const SizedBox(height: 14),
        GenerationWaitStoryHeader(
          viewModel: vm,
          presentation: presentation,
        ),
        const SizedBox(height: 14),
        ThemeAnticipationHero(
          viewModel: vm,
          width: size.width,
          height: size.height,
        ),
        const SizedBox(height: 16),
        _buildWaitStageFooter(vm, presentation),
      ],
    );
  }

  Widget _buildWaitStageFooter(
    PhotoGenerateViewModel vm,
    GenerationWaitPresentation presentation, {
    bool compact = false,
    bool showPolishStrip = false,
  }) {
    final showLiveStatus = !compact &&
        generationWaitShouldShowLiveStatusCopy(presentation);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showPolishStrip) ...[
          PostRevealPolishingOverlay(
            steps: vm.generationRunStepPreviews,
          ),
          const SizedBox(height: 10),
        ],
        if (showLiveStatus) _buildLiveStatusCopy(presentation),
        GenerationWaitEducationalFooter(
          elapsedSeconds: vm.elapsedSeconds,
          etaSnapshot: resolveGenerationEta(vm),
          compact: compact,
          hideFactWhenPolishing: showPolishStrip,
        ),
        if (!compact) ...[
          const SizedBox(height: 14),
          GenerationWaitThemePreviewReel(
            excludeThemeId: vm.selectedTheme?.id,
          ),
          GenerationWaitMarketingTagline(elapsedSeconds: vm.elapsedSeconds),
        ] else ...[
          const SizedBox(height: 10),
          GenerationWaitThemePreviewReel(
            excludeThemeId: vm.selectedTheme?.id,
          ),
        ],
      ],
    );
  }

  Widget _buildLiveStatusCopy(GenerationWaitPresentation presentation) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          children: [
            if (presentation.headline.isNotEmpty)
              Text(
                presentation.headline,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
                textAlign: TextAlign.center,
              ),
            if (presentation.description.isNotEmpty &&
                presentation.description.trim() !=
                    AppStrings.generationWaitExpectation &&
                presentation.description.trim() !=
                    AppStrings.generationWaitTimeExpectation) ...[
              const SizedBox(height: 4),
              Text(
                presentation.description,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  height: 1.25,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, PhotoGenerateViewModel vm) {
    final message = vm.errorMessage ?? AppStrings.generationWaitErrorTitle;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.cardWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_triangle,
            color: Colors.redAccent,
            size: 40,
          ),
          const SizedBox(height: 12),
          const Text(
            AppStrings.generationWaitErrorTitle,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text(AppStrings.generationWaitGoBack),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: () => _startOver(context),
              child: const Text(AppStrings.generationWaitStartOver),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startOver(BuildContext context) async {
    await endPhotoboothCustomerSessionLogged('generation_wait_start_over');
    if (!context.mounted) return;
    await Navigator.pushNamedAndRemoveUntil(
      context,
      AppConstants.kRouteTerms,
      (route) => false,
    );
  }
}

String generationWaitLoadingMessage(PhotoGenerateViewModel viewModel) {
  if (viewModel.progressMessage.isNotEmpty) {
    return viewModel.progressMessage;
  }
  if (viewModel.isLoadingMore) return 'Adding new style...';
  return generationWaitRotatingCopy(viewModel.elapsedSeconds);
}
