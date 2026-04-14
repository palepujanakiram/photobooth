import 'dart:math' as math;
import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoColors, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_settings_manager.dart';
import 'photo_generate_viewmodel.dart';
import '../theme_selection/theme_model.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/leading_with_alice.dart';
import '../../views/widgets/theme_background.dart';
import '../../utils/route_args.dart';
import '../../utils/secure_image_url.dart';

class PhotoGenerateScreen extends StatefulWidget {
  const PhotoGenerateScreen({super.key});

  @override
  State<PhotoGenerateScreen> createState() => _PhotoGenerateScreenState();
}

class _PhotoGenerateScreenState extends State<PhotoGenerateScreen> {
  /// Layout animations when zoom toggles (message strip, row height, footer shift).
  static const Duration _kZoomLayoutAnimationDuration =
      Duration(milliseconds: 280);
  static const Curve _kZoomLayoutAnimationCurve = Curves.easeOutCubic;

  /// Reserved height for Continue + “Or add one more style” so the bar stays fixed when cards zoom.
  static const double _kGenerateFooterSlotHeight = 140.0;

  late PhotoGenerateViewModel _viewModel;
  bool _viewModelCreated = false;
  bool _isInitialized = false;
  final GlobalKey _contentKey = GlobalKey();

  /// At most one zoomed slot: null or a [GeneratedImage.id].
  String? _zoomedSlotId;

  void _clearPhotoZoom() {
    if (_zoomedSlotId == null) return;
    setState(() => _zoomedSlotId = null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_viewModelCreated) {
      _viewModel = PhotoGenerateViewModel(
        appSettingsManager: context.read<AppSettingsManager>(),
      );
      _viewModelCreated = true;
    }
    if (!_isInitialized) {
      _initializeFromArguments();
      _isInitialized = true;
    }
  }

  void _initializeFromArguments() {
    final parsed = GenerateArgs.tryParse(ModalRoute.of(context)?.settings.arguments);
    if (parsed == null) return;
    _viewModel.initialize(parsed.photo, parsed.theme);

    // Start generation automatically
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewModel.generateImage();
    });
  }

  // Note: We previously derived per-image aspect ratios. Now that we always show
  // generated outputs in a consistent grid, this is no longer needed.

  void _showCancelConfirmation(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancel Process?'),
          content: const Text(
            'Are you sure you want to cancel? Your generated images will be lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.of(context).maybePop();
              },
              child: const Text('Yes', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _showCancelOperationDialog(BuildContext context, PhotoGenerateViewModel viewModel) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancel Generation?'),
          content: const Text(
            'An image is currently being generated. Do you want to cancel and go back?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Keep Waiting'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                viewModel.cancelOperation();
                Navigator.of(context).maybePop();
              },
              child: const Text('Cancel & Go Back', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

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
                'Generate Photo',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                ),
              ),
              leading: IconButton(
                icon: const Icon(CupertinoIcons.back, color: Colors.white),
                onPressed: () {
                  _clearPhotoZoom();
                  if (viewModel.isOperationInProgress) {
                    _showCancelOperationDialog(context, viewModel);
                  } else {
                    _showCancelConfirmation(context);
                  }
                },
              ),
              actions: const [AppBarAliceAction()],
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: ThemeBackground(theme: viewModel.selectedTheme),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: kToolbarHeight),
                    child: Column(
                      children: [
                        Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return _buildMainContent(
                                  context,
                                  viewModel,
                                  appColors,
                                  isLandscape,
                                  constraints.maxHeight,
                                  constraints.maxWidth,
                                );
                              },
                            ),
                          ),
                      ],
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

  Widget _buildMainContent(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors, [
    bool isLandscape = false,
    double? viewportHeight,
    double? viewportWidth,
  ]) {
    final padding = isLandscape ? 12.0 : 16.0;
    final maxWidth = viewportWidth != null && viewportWidth.isFinite ? viewportWidth : double.infinity;

    Widget buildContent(double width) {
      final contentWidth = width.isFinite ? width : null;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: Column(
              key: _contentKey,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPhotosDisplay(
                  context,
                  viewModel,
                  appColors,
                  isLandscape,
                  contentWidth,
                  viewportHeight,
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (viewportHeight != null && viewportHeight > 0) {
      final hasFooter = viewModel.generatedImages.isNotEmpty ||
          viewModel.isGenerating;
      final footerH = hasFooter ? _kGenerateFooterSlotHeight : 0.0;

      return Padding(
        padding: EdgeInsets.all(padding),
        child: LayoutBuilder(
          builder: (context, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, slot) {
                      final w = slot.maxWidth.isFinite && slot.maxWidth > 0
                          ? slot.maxWidth
                          : maxWidth;
                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: w),
                              child: Column(
                                key: _contentKey,
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment:
                                    CrossAxisAlignment.stretch,
                                children: [
                                  _buildPhotosDisplay(
                                    context,
                                    viewModel,
                                    appColors,
                                    isLandscape,
                                    w.isFinite ? w : null,
                                    viewportHeight,
                                    true,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                if (hasFooter)
                  SizedBox(
                    height: footerH,
                    child: Center(
                      child: _buildPhotosActionFooter(
                        context,
                        viewModel,
                        appColors,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth.isFinite ? constraints.maxWidth : maxWidth;
          return buildContent(w);
        },
      ),
    );
  }

  Widget _buildPhotosActionFooter(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
  ) {
    final canAddMoreStyle = viewModel.canShowAddAnotherStyleButton;
    final isGenerating = viewModel.isGenerating && viewModel.generatedImages.isEmpty;
    final isLoadingMore = viewModel.isLoadingMore;
    final isGeneratingOrLoading = isGenerating || isLoadingMore;

    return SizedBox(
      width: 320,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 16),
            color: (!isGeneratingOrLoading && viewModel.hasSelectedImages)
                ? CupertinoColors.systemBlue
                : CupertinoColors.systemGrey,
            borderRadius: BorderRadius.circular(12),
            onPressed: (!isGeneratingOrLoading && viewModel.hasSelectedImages)
                ? () {
                    _clearPhotoZoom();
                    final selectedImages = viewModel.selectedGeneratedImages;
                    if (selectedImages.isNotEmpty) {
                      Navigator.pushNamed(
                        context,
                        AppConstants.kRouteResult,
                        arguments: {
                          'generatedImages': selectedImages,
                          'originalPhoto': viewModel.originalPhoto,
                        },
                      );
                    }
                  }
                : null,
            child: Text(
              viewModel.selectedCount < viewModel.generatedImages.length
                  ? 'Continue (${viewModel.selectedCount} of ${viewModel.generatedImages.length})'
                  : 'Continue',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: CupertinoColors.white,
              ),
            ),
          ),
          if (viewModel.selectedCount > 0) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Total: ₹${viewModel.selectedTotalPrice}'
                '${viewModel.selectedCount > 1 ? '  (+₹${(viewModel.selectedCount - 1) * viewModel.additionalPrintPrice})' : ''}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (canAddMoreStyle) ...[
            const SizedBox(height: 8),
            Center(
              child: CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                onPressed: (viewModel.isGenerating || viewModel.isLoadingMore)
                    ? null
                    : () async {
                        _clearPhotoZoom();
                        final result = await Navigator.pushNamed(
                          context,
                          AppConstants.kRouteHome,
                          arguments: {
                            'addOneMoreStyle': true,
                            'usedThemeIds': List<String>.from(
                              viewModel.generatedImages
                                  .map((e) => e.theme.id),
                            ),
                          },
                        );
                        if (!mounted) return;
                        if (result is ThemeModel) {
                          viewModel.prepareToAddStyle(result);
                          viewModel.tryDifferentStyle(result);
                        }
                      },
                child: const Text(
                  'Or add one more style',
                  style: TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.systemBlue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
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
    // Portrait uses the theme card ratio. Landscape uses per-image aspect to avoid black bars.
    const double portraitAspect = AppConstants.kThemeSelectedCardAspectRatio;
    const double fallbackLandscapeAspect = 16 / 9;
    final double aspect = isLandscape ? fallbackLandscapeAspect : portraitAspect;

    final bool isGenerating = viewModel.isGenerating && viewModel.generatedImages.isEmpty;
    final bool isLoadingMore = viewModel.isLoadingMore;
    final bool isGeneratingOrLoading = isGenerating || isLoadingMore;

    final double vh = viewportHeight ?? MediaQuery.sizeOf(context).height;
    // Reduce reserved space so the photo canvas gets more prominence.
    const double reservedAboveRow = 72.0;
    const double reservedBelowRow = 172.0;
    // Landscape / large displays: let the photo row use more vertical space (kiosk).
    final double heightFraction = isLandscape ? 0.80 : 0.68;
    final double maxRowCap = isLandscape ? 1080.0 : 920.0;
    final double minRow = isLandscape ? 300.0 : 260.0;
    final double maxRowHeight = math.max(
      minRow,
      math.min(
        maxRowCap,
        math.min(
          vh * heightFraction,
          vh - reservedAboveRow - reservedBelowRow,
        ),
      ),
    );
    return _buildGeneratedOnlyLayout(
      context,
      viewModel,
      appColors,
      screenWidth: screenWidth,
      maxRowHeight: maxRowHeight,
      gap: cardGap,
      aspect: aspect,
      isGeneratingOrLoading: isGeneratingOrLoading,
      fixedFooterOutside: fixedFooterOutside,
    );
  }

  Widget _buildGeneratedOnlyLayout(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors, {
    required double screenWidth,
    required double maxRowHeight,
    required double gap,
    required double aspect,
    required bool isGeneratingOrLoading,
    required bool fixedFooterOutside,
  }) {
    final isGenerating = viewModel.isGenerating && viewModel.generatedImages.isEmpty;
    final isLoadingMore = viewModel.isLoadingMore;
    final images = viewModel.generatedImages;
    final hasImages = images.isNotEmpty;

    final totalSlots = (hasImages ? images.length : 1) + (isLoadingMore ? 1 : 0);

    // Responsive grid: 1 -> 1 col, 2 -> 2 cols, 3+ -> 3 cols (clamped by width).
    int cols = totalSlots <= 1 ? 1 : (totalSlots == 2 ? 2 : 3);
    cols = cols.clamp(1, 3);
    final rows = (totalSlots / cols).ceil().clamp(1, 3);

    // Compute card sizes from height budget; scale down if width would overflow.
    final gridH = maxRowHeight;
    final cardH = (gridH - gap * (rows - 1)) / rows;
    final cardW = cardH * aspect;
    final gridW = cols * cardW + gap * (cols - 1);
    final scale = gridW > screenWidth ? (screenWidth / gridW).clamp(0.35, 1.0) : 1.0;
    final scaledW = cardW * scale;
    final scaledH = cardH * scale;

    final String? genZoomId = _zoomedSlotId != null &&
            viewModel.generatedImages.any((e) => e.id == _zoomedSlotId)
        ? _zoomedSlotId
        : null;

    final slots = _buildTransformedSlotWidgets(
      context,
      viewModel,
      appColors,
      scaledW,
      scaledH,
      genZoomId,
    );

    final message = isGeneratingOrLoading
        ? (isLoadingMore
            ? 'Adding your new style...'
            : 'Please wait while we create your masterpiece')
        : hasImages
            ? 'Your masterpiece is ready'
            : '';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (message.isNotEmpty) ...[
            Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 18),
          ],
          AnimatedSize(
            duration: _kZoomLayoutAnimationDuration,
            curve: _kZoomLayoutAnimationCurve,
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            child: SizedBox(
              width: screenWidth,
              child: Center(
                child: Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  alignment: WrapAlignment.center,
                  children: slots,
                ),
              ),
            ),
          ),
          if ((hasImages || isGenerating || isLoadingMore) && !fixedFooterOutside) ...[
            const SizedBox(height: 18),
            _buildPhotosActionFooter(context, viewModel, appColors),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildTransformedSlotWidgets(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
    double cardWidth,
    double cardHeight,
    String? effectiveZoomId,
  ) {
    final isGenerating = viewModel.isGenerating && viewModel.generatedImages.isEmpty;
    final isLoadingMore = viewModel.isLoadingMore;
    final images = viewModel.generatedImages;
    final hasImages = images.isNotEmpty;

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
          effectiveZoomId: effectiveZoomId,
          showRemoveButton: showRemoveButton,
        ),
      );
    }
    return out;
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

  Widget _buildOneTransformedImageCard(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    GeneratedImage image,
    double cardWidth,
    double cardHeight, {
    required String? effectiveZoomId,
    bool showRemoveButton = false,
  }) {
    final isZoomed = effectiveZoomId == image.id;
    const double zoom = AppConstants.kGeneratePhotoZoomedScale;
    final double slotW = isZoomed ? cardWidth * zoom : cardWidth;
    final double slotH = isZoomed ? cardHeight * zoom : cardHeight;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: slotW,
      height: slotH,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _zoomedSlotId = _zoomedSlotId == image.id ? null : image.id;
          });
        },
        child: SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: image.isSelected
                    ? CupertinoColors.systemBlue.withValues(alpha: 0.85)
                    : Colors.white24,
                width: image.isSelected ? 2.0 : 1.0,
              ),
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                if (image.isSelected)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          boxShadow: [
                            BoxShadow(
                              color: CupertinoColors.systemBlue.withValues(alpha: 0.18),
                              blurRadius: 26,
                              spreadRadius: 2,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const ColoredBox(color: Colors.black),
                Image.network(
                  SecureImageUrl.withSessionId(image.imageUrl),
                  // Show the full generation in-frame (no crop).
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  width: double.infinity,
                  height: double.infinity,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(
                      CupertinoIcons.exclamationmark_triangle,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
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
                Positioned(
                  top: 10,
                  right: 10,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => viewModel.toggleImageSelection(image.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: image.isSelected
                              ? CupertinoColors.systemBlue.withValues(alpha: 0.92)
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
                                'Selected',
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
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
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
      ),
    );
  }

  Widget _buildTransformedLoadingPlaceholder(
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
  ) {
    final message = viewModel.progressMessage.isNotEmpty
        ? viewModel.progressMessage
        : (viewModel.isLoadingMore ? 'Adding new style...' : 'Creating...');
    return SizedBox.expand(
      child: ColoredBox(
        color: Colors.black26,
        child: Center(
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
      ),
    );
  }

}
