import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart' show CupertinoColors, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_settings_manager.dart';
import '../../services/kiosk_manager.dart';
import '../../views/widgets/kiosk_vertical_screen_layout.dart';
import 'photo_generate_view_widgets.dart';
import 'behold_result_ready_widgets.dart';
import 'generation_wait_widgets.dart';
import 'photo_generate_viewmodel.dart';
import 'post_reveal_polishing_overlay.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/leading_with_alice.dart';
import '../../views/widgets/theme_background.dart';
import '../../utils/route_args.dart';
import '../../utils/secure_image_url.dart';
import '../../utils/transformation_step_display.dart';
import '../../views/widgets/cached_network_image.dart';
import '../../views/widgets/generated_image_preview_screen.dart';
import '../photo_capture/photo_image_from_xfile_io.dart'
    if (dart.library.html) '../photo_capture/photo_image_from_xfile_web.dart' as photo_image;

/// Vertical space reserved above the behold card when the footer is external.
String _transformedLoadingMessage(PhotoGenerateViewModel viewModel) =>
    generationWaitLoadingMessage(viewModel);

double _computeBeholdMaxRowHeight({
  required bool fixedFooterOutside,
  required bool singleResultReady,
  required double viewportHeight,
  required double interiorChromeAboveCard,
  required bool isLandscape,
  required double reservedAboveRow,
  required double reservedBelowRow,
}) {
  if (fixedFooterOutside && singleResultReady) {
    return math.max(200.0, viewportHeight - interiorChromeAboveCard);
  }
  final heightFraction = isLandscape ? 0.80 : 0.68;
  final maxRowCap = isLandscape ? 1080.0 : 920.0;
  final rowBudget = math.min(
    maxRowCap,
    math.min(
      viewportHeight * heightFraction,
      viewportHeight -
          reservedAboveRow -
          reservedBelowRow -
          interiorChromeAboveCard,
    ),
  );
  return math.max(120.0, rowBudget);
}

double _interiorChromeAboveCardHeight({
  required bool fixedFooterOutside,
  required double? viewportHeight,
  required bool hasImages,
  required bool isGeneratingOrLoading,
}) {
  if (!fixedFooterOutside ||
      viewportHeight == null ||
      !viewportHeight.isFinite) {
    return 0.0;
  }
  if (hasImages && !isGeneratingOrLoading) return 0.0;
  if (isGeneratingOrLoading) return 88.0;
  return 0.0;
}

class PhotoGenerateScreen extends StatefulWidget {
  const PhotoGenerateScreen({super.key});

  @override
  State<PhotoGenerateScreen> createState() => _PhotoGenerateScreenState();
}

class _PhotoGenerateScreenState extends State<PhotoGenerateScreen> {
  /// AppBar [bottom]: subtitle line + optional stamp strip (must match [PreferredSize]).
  static const double _kBeholdSubtitleBlockHeight = 28.0;
  static const double _kBeholdStampStripExtraHeight = 62.0;

  double _beholdAppBarBelowTitleHeight(PhotoGenerateViewModel vm) {
    if (_beholdShowsReadySuccessHeader(vm)) {
      return kKioskAppBarReadyChromeHeight;
    }
    if (!vm.showProgressStampStrip) return _kBeholdSubtitleBlockHeight;
    return _kBeholdSubtitleBlockHeight + _kBeholdStampStripExtraHeight;
  }

  bool _beholdShowsReadySuccessHeader(PhotoGenerateViewModel vm) {
    final isGenerating =
        vm.isGenerating && vm.generatedImages.isEmpty;
    return vm.generatedImages.isNotEmpty && !isGenerating && !vm.isLoadingMore;
  }

  late PhotoGenerateViewModel _viewModel;
  bool _viewModelCreated = false;
  bool _isInitialized = false;
  final GlobalKey _contentKey = GlobalKey();

  bool? _paymentsEnabledOverride;

  void _openGeneratedImagePreview(
    BuildContext context,
    GeneratedImage image,
  ) {
    final url = SecureImageUrl.withSessionId(image.imageUrl);
    if (url.isEmpty) return;
    unawaited(
      Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          opaque: false,
          barrierColor: Colors.black.withValues(alpha: 0.92),
          pageBuilder: (_, __, ___) {
            return GeneratedImagePreviewScreen(
              imageUrl: url,
              title: image.theme.name,
              subtitle: 'Generated in ${_viewModel.elapsedSeconds}s',
            );
          },
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: child,
            );
          },
        ),
      ),
    );
  }

  /// Multi-style grid uses 3:2 slots; single results use [beholdSingleResultCardAspectRatio].
  double _beholdCardAspectRatio(BuildContext context, int slotCount) {
    return 3 / 2;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rawArgs = ModalRoute.of(context)?.settings.arguments;
    if (rawArgs is PhotoGenerateViewModel) {
      final isFirstBind = !_viewModelCreated;
      _viewModel = rawArgs;
      _viewModelCreated = true;
      _isInitialized = true;
      if (isFirstBind) {
        unawaited(_loadPaymentEnablement());
      }
      unawaited(_viewModel.refreshBeholdHeroAspectRatio());
      return;
    }
    if (!_viewModelCreated) {
      _viewModel = PhotoGenerateViewModel(
        appSettingsManager: context.read<AppSettingsManager>(),
      );
      _viewModelCreated = true;
      unawaited(_viewModel.loadProgressiveDisplayPreference());
      unawaited(_loadPaymentEnablement());
    }
    if (!_isInitialized) {
      _initializeFromArguments();
      _isInitialized = true;
    }
  }

  Future<void> _loadPaymentEnablement() async {
    final v = await KioskManager().getPaymentEnabledOverride();
    if (!mounted) return;
    setState(() => _paymentsEnabledOverride = v);
  }

  void _initializeFromArguments() {
    // `/generate` is now result-only. If someone navigates here with GenerateArgs,
    // redirect them to the progress route.
    final raw = ModalRoute.of(context)?.settings.arguments;
    final parsed = GenerateArgs.tryParse(raw);
    if (parsed == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AppConstants.kRouteGenerateProgress,
        arguments: parsed,
      );
    });
  }

  // Note: We previously derived per-image aspect ratios. Now that we always show
  // generated outputs in a consistent grid, this is no longer needed.

  void _showRemoveStyleConfirmation(
    BuildContext context, {
    required String themeName,
    required VoidCallback onConfirm,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove this style?'),
          content: Text(
            'Remove "$themeName" from your generated photos? You can add it again later with "Add one more style".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                onConfirm();
              },
              child: const Text('Remove', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Consumer<PhotoGenerateViewModel>(
        builder: (context, viewModel, child) {
          if (viewModel.hasError) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && viewModel.hasError) {
                AppSnackBar.showError(
                  context,
                  viewModel.errorMessage ?? 'Generation failed',
                );
                viewModel.clearError();
              }
            });
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
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(
                  _beholdAppBarBelowTitleHeight(viewModel),
                ),
                child: _buildBeholdAppBarBottom(context, viewModel),
              ),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  tooltip: viewModel.useProgressiveGenerationUi
                      ? 'Switch to simple progress'
                      : 'Switch to stage previews',
                  icon: Icon(
                    viewModel.useProgressiveGenerationUi
                        ? Icons.view_compact
                        : Icons.view_timeline,
                    color: Colors.white,
                  ),
                    onPressed: () async {
                    await viewModel.toggleProgressiveGenerationUi();
                  },
                ),
                const AppBarAliceAction(),
              ],
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: ThemeBackground(theme: viewModel.selectedTheme),
                ),
                Positioned.fill(
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: MediaQuery.paddingOf(context).top +
                            kToolbarHeight +
                            _beholdAppBarBelowTitleHeight(viewModel),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (_beholdShowsReadySuccessHeader(viewModel)) {
                            return buildBeholdReadyScreenLayout(
                              context: context,
                              constraints: constraints,
                              input: _photoGenerateMainContentInput(
                                viewModel,
                                appColors,
                                isLandscape,
                                viewportHeight: constraints.maxHeight,
                                viewportWidth: constraints.maxWidth,
                              ),
                            );
                          }
                          final media = MediaQuery.sizeOf(context);
                          final viewportH =
                              constraints.maxHeight.isFinite &&
                                      constraints.maxHeight > 0
                                  ? constraints.maxHeight
                                  : media.height * 0.65;
                          final viewportW =
                              constraints.maxWidth.isFinite &&
                                      constraints.maxWidth > 0
                                  ? constraints.maxWidth
                                  : media.width;
                          return _buildMainContent(
                            context,
                            viewModel,
                            appColors,
                            isLandscape,
                            viewportH,
                            viewportW,
                          );
                        },
                      ),
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

  Widget _buildBeholdAppBarBottom(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
  ) {
    if (_beholdShowsReadySuccessHeader(viewModel)) {
      return const BeholdReadyCompactAppBarChrome();
    }
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text(
            'Your AI-transformed portrait awaits',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  // Note: legacy pipeline stamp widget removed (wait UX is now the progress page).

  Widget? _generatingHeroUnderlay(PhotoGenerateViewModel vm) =>
      generatingHeroUnderlay(vm);

  Widget _buildMainContent(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors, [
    bool isLandscape = false,
    double? viewportHeight,
    double? viewportWidth,
  ]) {
    return buildPhotoGenerateMainContent(
      context: context,
      input: _photoGenerateMainContentInput(
        viewModel,
        appColors,
        isLandscape,
        viewportHeight: viewportHeight,
        viewportWidth: viewportWidth,
      ),
    );
  }

  PhotoGenerateMainContentInput _photoGenerateMainContentInput(
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
    bool isLandscape, {
    double? viewportHeight,
    double? viewportWidth,
  }) {
    return PhotoGenerateMainContentInput(
      contentKey: _contentKey,
      viewModel: viewModel,
      appColors: appColors,
      isLandscape: isLandscape,
      viewportHeight: viewportHeight,
      viewportWidth: viewportWidth,
      buildPhotosDisplay: _buildPhotosDisplay,
      buildPhotosActionFooter: _buildPhotosActionFooter,
      beholdReadyActions: BeholdReadyActionInput(
        paymentsEnabled: _paymentsEnabledOverride ?? true,
        isMounted: mounted,
        onAddStyleSelected: (theme) {
          viewModel.prepareToAddStyle(theme);
          viewModel.tryDifferentStyle(theme);
        },
      ),
      buildBeholdReadyHero: (ctx, vm, {required width, required height}) {
        return buildBeholdReadyHeroWidget(
          context: ctx,
          viewModel: vm,
          appColors: appColors,
          width: width,
          height: height,
          buildTransformedSlotWidgets: _buildTransformedSlotWidgets,
        );
      },
    );
  }

  Widget _buildPhotosActionFooter(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
  ) {
    return buildPhotosActionFooter(
      context: context,
      viewModel: viewModel,
      paymentsEnabled: _paymentsEnabledOverride ?? true,
      isMounted: mounted,
      onAddStyleSelected: (theme) {
        viewModel.prepareToAddStyle(theme);
        viewModel.tryDifferentStyle(theme);
      },
    );
  }

  Widget _buildPhotosDisplay(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors, [
    bool isLandscape = false,
    double? availableWidth,
    double? viewportHeight,
    bool fixedFooterOutside = false,
  ]) {
    // Slightly tighter padding so cards use more canvas (kiosk-friendly).
    final double sectionPadding = isLandscape ? 10.0 : 12.0;
    final screenWidth = availableWidth ??
        (MediaQuery.sizeOf(context).width - 2 * sectionPadding).clamp(0.0, double.infinity);

    const double cardGap = 10.0;

    final bool isGenerating = viewModel.isGenerating && viewModel.generatedImages.isEmpty;
    final bool isLoadingMore = viewModel.isLoadingMore;
    final bool isGeneratingOrLoading = isGenerating || isLoadingMore;

    final double vh = viewportHeight ?? MediaQuery.sizeOf(context).height;
    // Reduce reserved space so the photo canvas gets more prominence.
    const double reservedAboveRow = 72.0;
    final double reservedBelowRow = fixedFooterOutside ? 24.0 : 172.0;
    // When the action footer is laid out below this column, titles and status
    // ("Your masterpiece is ready", elapsed time, etc.) still sit above the hero
    // card inside the same Expanded slot. Reserve vertical budget for them so the
    // Column does not overflow short viewports (kiosk / embedded browser).
    final bool hasImages = viewModel.generatedImages.isNotEmpty;
    final double interiorChromeAboveCard = _interiorChromeAboveCardHeight(
      fixedFooterOutside: fixedFooterOutside,
      viewportHeight: viewportHeight,
      hasImages: hasImages,
      isGeneratingOrLoading: isGeneratingOrLoading,
    );
    final bool singleResultReady =
        hasImages && !isGeneratingOrLoading && viewModel.generatedImages.length <= 1;

    final layout = GeneratedOnlyLayoutLayout(
      screenWidth: screenWidth,
      maxRowHeight: _computeBeholdMaxRowHeight(
        fixedFooterOutside: fixedFooterOutside,
        singleResultReady: singleResultReady,
        viewportHeight: vh,
        interiorChromeAboveCard: interiorChromeAboveCard,
        isLandscape: isLandscape,
        reservedAboveRow: reservedAboveRow,
        reservedBelowRow: reservedBelowRow,
      ),
      gap: cardGap,
      isGeneratingOrLoading: isGeneratingOrLoading,
      fixedFooterOutside: fixedFooterOutside,
    );
    return buildGeneratedOnlyLayout(
      context: context,
      viewModel: viewModel,
      appColors: appColors,
      layout: layout,
      builders: GeneratedOnlyLayoutBuilders(
        beholdCardAspectRatio: _beholdCardAspectRatio,
        buildTransformedSlotWidgets: _buildTransformedSlotWidgets,
        buildProgressivePipelineSection: _buildProgressivePipelineSection,
        buildLiveGenerationHeader: _buildLiveGenerationHeader,
        buildGenerationProgressHeroCard: _buildGenerationProgressHeroCard,
        buildGenerationStoryCard: _buildGenerationStoryCard,
        buildPhotosActionFooter: _buildPhotosActionFooter,
      ),
    );
  }

  List<Widget> _buildTransformedSlotWidgets(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
    double cardWidth,
    double cardHeight,
  ) {
    final isGenerating = viewModel.isGenerating && viewModel.generatedImages.isEmpty;
    final isLoadingMore = viewModel.isLoadingMore;
    final images = viewModel.generatedImages;
    final hasImages = images.isNotEmpty;

    if (isGenerating && !hasImages && viewModel.liveSlotCount > 0) {
      return viewModel.liveSlots
          .map(
            (slot) => _transformedSlotFrame(
              cardWidth: cardWidth,
              cardHeight: cardHeight,
              child: _buildLiveGenerationSlot(
                viewModel,
                appColors,
                slot,
              ),
            ),
          )
          .toList();
    }

    if (isGenerating && !hasImages) {
      return [
        _transformedSlotFrame(
          cardWidth: cardWidth,
          cardHeight: cardHeight,
          child: _buildTransformedLoadingPlaceholder(viewModel, appColors),
        ),
      ];
    }

    if (!hasImages) {
      return [
        _transformedSlotFrame(
          cardWidth: cardWidth,
          cardHeight: cardHeight,
          child: const Center(
            child: Icon(
              Icons.photo_outlined,
              size: 48,
              color: Colors.white54,
            ),
          ),
        ),
      ];
    }

    const bool showRemoveButton = false;
    final spotlightReady = images.length == 1 && !isLoadingMore && !isGenerating;
    final out = <Widget>[];
    if (isLoadingMore) {
      out.add(
        _transformedSlotFrame(
          cardWidth: cardWidth,
          cardHeight: cardHeight,
          child: _buildTransformedLoadingPlaceholder(viewModel, appColors),
        ),
      );
    }
    for (final image in images) {
      out.add(
        _buildOneTransformedImageCard(
          context,
          viewModel,
          image,
          cardWidth,
          cardHeight,
          showRemoveButton: showRemoveButton,
          spotlightReadyLayout: spotlightReady,
        ),
      );
    }
    return out;
  }

  Widget _transformedSlotFrame({
    required double cardWidth,
    required double cardHeight,
    required Widget child,
    bool selected = false,
    bool emphasizeReadyGlow = false,
  }) {
    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: DecoratedBox(
        decoration: beholdReadyHeroFrameDecoration(
          selected: selected,
          emphasizeGlow: emphasizeReadyGlow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            emphasizeReadyGlow ? 13 : 11,
          ),
          child: child,
        ),
      ),
    );
  }

  /// Fills the hero card like CAPTURE / generation progress (cover, no letterbox mat).
  Widget _buildGeneratedHeroNetworkImage(
    BuildContext context, {
    required String imageUrl,
    required double width,
    required double height,
  }) {
    final secureUrl = SecureImageUrl.withSessionId(imageUrl);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheW = (width * dpr).ceil().clamp(64, 2048);
    final loading = ColoredBox(
      color: Colors.black,
      child: SizedBox(
        width: width,
        height: height,
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          ),
        ),
      ),
    );
    if (secureUrl.isEmpty) {
      return loading;
    }
    return SizedBox(
      width: width,
      height: height,
      child: ClipRect(
        child: ColoredBox(
          color: Colors.black,
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            child: CachedNetworkImage(
              imageUrl: secureUrl,
              fit: BoxFit.cover,
              cacheWidth: cacheW,
              filterQuality: FilterQuality.medium,
              placeholder: loading,
              errorWidget: SizedBox(
                width: width,
                height: height,
                child: const Center(
                  child: Icon(
                    CupertinoIcons.exclamationmark_triangle,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOneTransformedImageCard(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    GeneratedImage image,
    double cardWidth,
    double cardHeight, {
    bool showRemoveButton = false,
    bool spotlightReadyLayout = false,
  }) {
    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openGeneratedImagePreview(context, image),
          child: _transformedSlotFrame(
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            selected: image.isSelected,
            emphasizeReadyGlow: spotlightReadyLayout,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                _buildGeneratedHeroNetworkImage(
                  context,
                  imageUrl: image.imageUrl,
                  width: cardWidth,
                  height: cardHeight,
                ),
                if (showRemoveButton)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.white,
                      elevation: 2,
                      shadowColor: Colors.black38,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: () => _showRemoveStyleConfirmation(
                          context,
                          themeName: image.theme.name,
                          onConfirm: () =>
                              viewModel.removeGeneratedImage(image.id),
                        ),
                        customBorder: const CircleBorder(),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            CupertinoIcons.trash_fill,
                            color: Colors.black87,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!spotlightReadyLayout)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _openGeneratedImagePreview(context, image),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            CupertinoIcons.fullscreen,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: spotlightReadyLayout ? null : 10,
                  bottom: spotlightReadyLayout ? 12 : null,
                  right: 12,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => viewModel.toggleImageSelection(image.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: image.isSelected
                              ? kBeholdReadyAccent.withValues(alpha: 0.92)
                              : Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: image.isSelected
                                ? Colors.white.withValues(alpha: 0.25)
                                : Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              image.isSelected
                                  ? CupertinoIcons.check_mark
                                  : CupertinoIcons.circle,
                              size: 14,
                              color: Colors.white,
                            ),
                            if (image.isSelected) ...[
                              const SizedBox(width: 6),
                              const Text(
                                AppStrings.beholdSelectedLabel,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                if (spotlightReadyLayout)
                  Positioned(
                    left: 14,
                    bottom: 14,
                    right: 88,
                    child: Text(
                      image.theme.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        shadows: [
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  )
                else
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 8,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.7),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Text(
                        image.theme.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressivePipelineSection(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
  ) {
    final stages = viewModel.progressivePipelineStages;
    final progress = (viewModel.liveProgress / 100).clamp(0.0, 1.0);
    final caption = viewModel.progressiveOneLiner;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress <= 0 ? null : progress,
              minHeight: 6,
              backgroundColor: Colors.white24,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 118,
            child: stages.isEmpty
                ? Center(
                    child: Text(
                      'Pipeline starting — watch each stage appear here.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: stages.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      return _buildProgressiveStageTile(context, stages[i]);
                    },
                  ),
          ),
          if (caption != null && caption.isNotEmpty) ...[
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: Text(
                caption,
                key: ValueKey<String>(caption),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.25,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressiveStageTile(
    BuildContext context,
    ProgressivePipelineStage stage,
  ) {
    final label = transformationStepDisplayLabel(stage.stepKey);
    final url = stage.previewImageUrl;

    Widget thumb;
    if (url != null && url.isNotEmpty) {
      thumb = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: SecureImageUrl.withSessionId(url),
          fit: BoxFit.cover,
          width: 72,
          height: 72,
        ),
      );
    } else if (stage.complete && !stage.skipped) {
      thumb = Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: const Icon(Icons.check_circle, color: Colors.lightGreenAccent, size: 36),
      );
    } else if (stage.skipped) {
      thumb = Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: const Icon(Icons.skip_next, color: Colors.white38, size: 32),
      );
    } else if (stage.active) {
      thumb = Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amberAccent, width: 2),
        ),
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          ),
        ),
      );
    } else {
      thumb = Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Icon(
          transformationStepIcon(stage.stepKey),
          color: Colors.white38,
          size: 32,
        ),
      );
    }

    return SizedBox(
      width: 82,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          thumb,
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: stage.skipped ? Colors.white38 : Colors.white70,
              fontSize: 10,
              decoration:
                  stage.skipped ? TextDecoration.lineThrough : TextDecoration.none,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (stage.durationMs != null && stage.complete)
            Text(
              '${stage.durationMs} ms',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 9,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLiveGenerationHeader(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
  ) {
    final step = viewModel.liveCurrentStep;
    final commentary = viewModel.liveCommentary;
    final attempt = viewModel.liveAttempt;
    final totalAttempts = viewModel.liveTotalAttempts;
    final lastScore = viewModel.liveLastScore;
    final progress = (viewModel.liveProgress / 100).clamp(0.0, 1.0);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress <= 0 ? null : progress,
              minHeight: 6,
              backgroundColor: Colors.white24,
              color: Colors.white,
            ),
          ),
          if (step != null && step.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Step: ${transformationStepDisplayLabel(step)}'
              '${viewModel.liveStepDurationsMs[step] != null ? ' · ${viewModel.liveStepDurationsMs[step]} ms' : ''}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (attempt != null &&
              totalAttempts != null &&
              totalAttempts > 1) ...[
            const SizedBox(height: 6),
            Text(
              'Attempt $attempt of $totalAttempts'
              '${lastScore != null ? ' · last score ${lastScore.toStringAsFixed(2)}' : ''}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (commentary != null && commentary.isNotEmpty) ...[
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: Text(
                commentary,
                key: ValueKey<String>(commentary),
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveGenerationSlot(
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
    LiveGenerationSlotState slot,
  ) {
    if (slot.loading) {
      return _buildTransformedLoadingPlaceholder(viewModel, appColors);
    }
    if (slot.failed) {
      return const Center(
        child: Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
      );
    }
    final url = slot.imageUrl;
    if (url == null || url.isEmpty) {
      return const Center(
        child: Icon(Icons.image_not_supported_outlined,
            color: Colors.white38, size: 40),
      );
    }
    final secureUrl = SecureImageUrl.withSessionId(url);
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: secureUrl,
          fit: BoxFit.cover,
        ),
        if (slot.qualityScore != null)
          Positioned(
            top: 8,
            right: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  slot.qualityScore!.toStringAsFixed(2),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTransformedLoadingPlaceholder(
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
  ) {
    final message = _transformedLoadingMessage(viewModel);
    final underlay = _generatingHeroUnderlay(viewModel);
    final photo = viewModel.originalPhoto;
    final captureUnderlay = underlay == null && photo != null
        ? ColoredBox(
            color: Colors.black,
            child: KenBurnsCaptureImage(
              imageFile: photo.imageFile,
              width: 720,
              height: 1080,
            ),
          )
        : null;
    final baseUnderlay = underlay ?? captureUnderlay;
    final hint = viewModel.selectedHeroStampId != null &&
            underlay == null
        ? 'Preview not ready for this step yet'
        : null;
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (baseUnderlay != null) Positioned.fill(child: baseUnderlay),
          Positioned.fill(
            child: ColoredBox(
              color: baseUnderlay != null
                  ? Colors.black.withValues(alpha: 0.42)
                  : Colors.black26,
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${viewModel.elapsedSeconds}s',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerationStoryCard(
    BuildContext context,
    PhotoGenerateViewModel vm,
  ) {
    final screenW = MediaQuery.sizeOf(context).width;
    final maxW = math.min(screenW * 0.44, 560.0);
    return GenerationPipelineStoryCard(
      viewModel: vm,
      commentaryEnabled: vm.generationCommentaryEnabledForWait,
      maxWidth: maxW,
      onStampTap: (index) => vm.toggleHeroStamp('funnel:$index'),
    );
  }

  Widget _buildGenerationProgressHeroCard(
    BuildContext context,
    PhotoGenerateViewModel vm, {
    required double width,
    required double height,
  }) {
    // Use the same hero frame as the final image card; swap the "content" inside.
    final preprocessUrl = _previewForStage(vm, 'preprocessing');
    final bgUrl = _previewForStage(vm, 'background_removal');
    final aiUrl = _previewForStage(vm, 'ai_generation');

    int index = 0;
    String stageTitle = '2 · CAPTURE';
    String headline = 'Got it';
    String description = 'Frozen frame, framing applied';
    String? imageUrl;
    Widget? bottomAccessory;

    if (aiUrl != null) {
      index = 3;
      stageTitle = '4 · REVEAL';
      headline = 'Rendering';
      description = 'AI is applying your style';
      imageUrl = aiUrl;
      bottomAccessory =
          PostRevealPolishingOverlay(steps: vm.generationRunStepPreviews);
    } else if (bgUrl != null) {
      index = 2;
      stageTitle = '3 · ISOLATE';
      headline = 'Background removed';
      description = 'Subject isolated, ready to render';
      imageUrl = bgUrl;
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

    // Important UX: keep the photo canvas clean (no UI overlays).
    // All progress/status UI lives around the canvas, not on top of it.
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
                        child: _buildProgressHeroStageImage(
                          context,
                          vm,
                          imageUrl: imageUrl,
                          width: width,
                          height: height,
                        ),
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

  Widget _buildProgressHeroStageImage(
    BuildContext context,
    PhotoGenerateViewModel vm, {
    required String? imageUrl,
    required double width,
    required double height,
  }) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheW = (width * dpr).ceil().clamp(64, 2048);
    final loading = ColoredBox(
      color: Colors.black,
      child: SizedBox(
        width: width,
        height: height,
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          ),
        ),
      ),
    );
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final err = SizedBox(
        width: width,
        height: height,
        child: vm.originalPhoto != null
            ? photo_image.imageFromXFileSized(
                vm.originalPhoto!.imageFile,
                width,
                height,
                fit: BoxFit.cover,
              )
            : loading,
      );
      return SizedBox(
        width: width,
        height: height,
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            child: CachedNetworkImage(
              imageUrl: imageUrl.trim(),
              fit: BoxFit.cover,
              cacheWidth: cacheW,
              filterQuality: FilterQuality.medium,
              placeholder: loading,
              errorWidget: err,
            ),
          ),
        ),
      );
    }
    if (vm.originalPhoto != null) {
      return photo_image.imageFromXFileSized(
        vm.originalPhoto!.imageFile,
        width,
        height,
        fit: BoxFit.cover,
      );
    }
    return loading;
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

}

