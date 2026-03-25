import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoColors, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'photo_generate_viewmodel.dart';
import '../photo_capture/photo_model.dart';
import '../theme_selection/theme_model.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/leading_with_alice.dart';
import '../../views/widgets/theme_background.dart';

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
  Uint8List? _originalPhotoBytes;
  bool _isInitialized = false;
  final GlobalKey _contentKey = GlobalKey();
  /// Sentinel when the captured photo slot is zoomed (vs a [GeneratedImage.id]).
  static const String _kZoomOriginalSlotId = '__original_photo__';

  /// At most one zoomed slot: null, [_kZoomOriginalSlotId], or a generated image id.
  String? _zoomedSlotId;

  void _clearPhotoZoom() {
    if (_zoomedSlotId == null) return;
    setState(() => _zoomedSlotId = null);
  }

  @override
  void initState() {
    super.initState();
    _viewModel = PhotoGenerateViewModel();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _initializeFromArguments();
      _isInitialized = true;
    }
  }

  void _initializeFromArguments() {
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args != null && args is Map) {
      final photo = args['photo'] as PhotoModel?;
      final theme = args['theme'] as ThemeModel?;
      
      if (photo != null && theme != null) {
        _viewModel.initialize(photo, theme);
        _loadOriginalPhoto(photo);
        
        // Start generation automatically
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _viewModel.generateImage();
        });
      }
    }
  }

  Future<void> _loadOriginalPhoto(PhotoModel photo) async {
    try {
      final bytes = await photo.imageFile.readAsBytes();
      if (mounted) {
        setState(() {
          _originalPhotoBytes = Uint8List.fromList(bytes);
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

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
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  AppConstants.kRouteTerms,
                  (route) => false,
                );
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
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  AppConstants.kRouteTerms,
                  (route) => false,
                );
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
    final canAddMoreStyle = viewModel.generatedImages.length < 3;
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
            child: const Text(
              'Continue',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: CupertinoColors.white,
              ),
            ),
          ),
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
    final double sectionPadding = isLandscape ? 12.0 : 16.0;
    final screenWidth = availableWidth ??
        (MediaQuery.sizeOf(context).width - 2 * sectionPadding).clamp(0.0, double.infinity);

    const double lightningWidth = 36.0;
    const double cardGap = 12.0;
    const double aspect = AppConstants.kThemeSelectedCardAspectRatio;

    /// Matches centered theme card: carousel page width × peak center scale.
    final double themeReferenceCardWidth = screenWidth *
        AppConstants.kThemeCarouselViewportFraction *
        AppConstants.kThemeCarouselCenterMaxScale;

    final bool isGenerating = viewModel.isGenerating && viewModel.generatedImages.isEmpty;
    final bool isLoadingMore = viewModel.isLoadingMore;
    final bool hasResult = viewModel.generatedImages.isNotEmpty;
    final bool isGeneratingOrLoading = isGenerating || isLoadingMore;

    final int transformedSlotCount = !hasResult
        ? 1
        : viewModel.generatedImages.length + (isLoadingMore ? 1 : 0);

    final double vh = viewportHeight ?? MediaQuery.sizeOf(context).height;
    const double reservedAboveRow = 88.0;
    const double reservedBelowRow = 188.0;
    final double maxRowHeight = math.max(
      260.0,
      math.min(
        920.0,
        math.min(
          vh * 0.62,
          vh - reservedAboveRow - reservedBelowRow,
        ),
      ),
    );

    final int gapCount = 1 + transformedSlotCount;
    double cardWidth = (screenWidth - lightningWidth - cardGap * gapCount) /
        (1 + transformedSlotCount);
    cardWidth = math.max(cardWidth, themeReferenceCardWidth);
    double cardHeight = cardWidth / aspect;
    if (cardHeight > maxRowHeight) {
      cardHeight = maxRowHeight;
      cardWidth = cardHeight * aspect;
    }

    final String? genZoomId = _zoomedSlotId != null &&
            _zoomedSlotId != _kZoomOriginalSlotId &&
            viewModel.generatedImages.any((e) => e.id == _zoomedSlotId)
        ? _zoomedSlotId
        : null;

    final Widget originalCard = _buildCaptureCard(
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      isZoomed: _zoomedSlotId == _kZoomOriginalSlotId,
    );

    final Widget lightningIcon = SizedBox(
      width: lightningWidth,
      child: Center(
        child: Icon(
          CupertinoIcons.bolt_fill,
          size: 36,
          color: Colors.amber.shade400,
        ),
      ),
    );

    final List<Widget> transformedChildren = _buildTransformedRowChildren(
      context,
      viewModel,
      appColors,
      cardWidth,
      cardHeight,
      genZoomId,
    );

    final double rowIntrinsicWidth = _intrinsicPhotoRowWidth(
      cardWidth: cardWidth,
      cardGap: cardGap,
      lightningWidth: lightningWidth,
      zoomSlotId: _zoomedSlotId,
      viewModel: viewModel,
      isLoadingMore: isLoadingMore,
    );
    final double rowHorizontalPad =
        math.max(0.0, (screenWidth - rowIntrinsicWidth) / 2);

    final String messageBelow = isGeneratingOrLoading
        ? (isLoadingMore
            ? 'Adding your new style...'
            : 'Please wait while we create your masterpiece')
        : hasResult
            ? 'Your masterpiece is ready'
            : '';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (messageBelow.isNotEmpty) ...[
            hasResult
                ? Text(
                    messageBelow,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text(
                    messageBelow,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
            const SizedBox(height: 24),
          ],
          AnimatedSize(
            duration: _kZoomLayoutAnimationDuration,
            curve: _kZoomLayoutAnimationCurve,
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            child: SizedBox(
              width: screenWidth,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: rowHorizontalPad),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      originalCard,
                      const SizedBox(width: cardGap),
                      lightningIcon,
                      const SizedBox(width: cardGap),
                      ...transformedChildren,
                    ],
                  ),
                ),
              ),
            ),
          ),
          if ((hasResult || isGenerating) && !fixedFooterOutside) ...[
            const SizedBox(height: 24),
            _buildPhotosActionFooter(context, viewModel, appColors),
          ],
        ],
      ),
    );
  }

  /// Total width of [original][gap][lightning][gap][transformed…] for centering / scroll.
  double _intrinsicPhotoRowWidth({
    required double cardWidth,
    required double cardGap,
    required double lightningWidth,
    required String? zoomSlotId,
    required PhotoGenerateViewModel viewModel,
    required bool isLoadingMore,
  }) {
    const z = AppConstants.kGeneratePhotoZoomedScale;
    final double origW =
        zoomSlotId == _kZoomOriginalSlotId ? cardWidth * z : cardWidth;
    double w = origW + cardGap + lightningWidth + cardGap;

    if (viewModel.generatedImages.isEmpty) {
      return w + cardWidth;
    }

    final images = viewModel.generatedImages;
    if (isLoadingMore) {
      w += cardWidth;
    }
    for (var i = 0; i < images.length; i++) {
      if (isLoadingMore || i > 0) w += cardGap;
      final slotW = zoomSlotId == images[i].id ? cardWidth * z : cardWidth;
      w += slotW;
    }
    return w;
  }

  Widget _buildCaptureCard({
    required double cardWidth,
    required double cardHeight,
    required bool isZoomed,
  }) {
    const double z = AppConstants.kGeneratePhotoZoomedScale;
    final double slotW = isZoomed ? cardWidth * z : cardWidth;
    final double slotH = isZoomed ? cardHeight * z : cardHeight;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: slotW,
      height: slotH,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _zoomedSlotId =
                _zoomedSlotId == _kZoomOriginalSlotId ? null : _kZoomOriginalSlotId;
          });
        },
        child: SizedBox.expand(
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_originalPhotoBytes != null)
                    Image.memory(
                      _originalPhotoBytes!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                    )
                  else
                    const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
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

  /// Widgets to place after the lightning gap in the main photo [Row] (includes gaps between slots).
  List<Widget> _buildTransformedRowChildren(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
    double cardWidth,
    double cardHeight,
    String? effectiveZoomId,
  ) {
    const double innerGap = 12.0;
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
    // Loading slot first so it matches stack order (new prepended images appear here).
    if (isLoadingMore) {
      out.add(
        _transformedSlotFrame(
          cardWidth: cardWidth,
          cardHeight: cardHeight,
          child: _buildTransformedLoadingPlaceholder(viewModel, appColors),
        ),
      );
    }
    for (var i = 0; i < images.length; i++) {
      if (isLoadingMore || i > 0) out.add(const SizedBox(width: innerGap));
      out.add(
        _buildOneTransformedImageCard(
          context,
          viewModel,
          images[i],
          cardWidth,
          cardHeight,
          effectiveZoomId: effectiveZoomId,
          showRemoveButton: showRemoveButton,
        ),
      );
    }
    return out;
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
              child: Stack(
                fit: StackFit.expand,
                children: [
                Image.network(
                  image.imageUrl,
                  fit: BoxFit.cover,
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
