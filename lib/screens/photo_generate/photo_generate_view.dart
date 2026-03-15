import 'dart:typed_data';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
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
  late PhotoGenerateViewModel _viewModel;
  Uint8List? _originalPhotoBytes;
  bool _isInitialized = false;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _contentKey = GlobalKey();
  bool _hasScrolledToCenter = false;

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

  @override
  void dispose() {
    _scrollController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _scrollToCenterIfNeeded(double viewportHeight) {
    if (!mounted || _scrollController.hasClients == false) return;
    final renderObject = _contentKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final contentHeight = renderObject.size.height;
    if (contentHeight >= viewportHeight) return;
    final offset = (viewportHeight - contentHeight) / 2;
    if (offset > 0) {
      _scrollController.jumpTo(offset);
    }
    _hasScrolledToCenter = true;
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
                _buildPhotosDisplay(context, viewModel, appColors, isLandscape, contentWidth),
              ],
            ),
          ),
        ],
      );
    }

    if (viewportHeight != null && viewportHeight > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_hasScrolledToCenter && mounted) {
          _scrollToCenterIfNeeded(viewportHeight);
        }
      });
      return SingleChildScrollView(
        controller: _scrollController,
        padding: EdgeInsets.all(padding),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: viewportHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth.isFinite ? constraints.maxWidth : maxWidth;
                  return buildContent(w);
                },
              ),
            ],
          ),
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

  Widget _buildPhotosDisplay(BuildContext context, PhotoGenerateViewModel viewModel, AppColors appColors, [bool isLandscape = false, double? availableWidth]) {
    final double sectionPadding = isLandscape ? 12.0 : 16.0;
    // Use available width; when null, subtract padding so row never overflows when placed in padded layout
    final screenWidth = availableWidth ??
        (MediaQuery.sizeOf(context).width - 2 * sectionPadding).clamp(0.0, double.infinity);
    final isTablet = screenWidth > AppConstants.kTabletBreakpoint;

    // Card size so full row fits: 1 original + up to 4 transformed (3 images + loading card) + lightning + paddings
    const double lightningWidth = 60.0;
    const double cardGap = 12.0;
    const double minCardWidth = 72.0;
    const double maxCardWidthPhone = 130.0;
    const double maxCardWidthTablet = 160.0;
    const double overflowSafetyMargin = 32.0; // avoid right overflow (e.g. scrollbar, rounding)
    final double maxCardWidth = isTablet ? maxCardWidthTablet : maxCardWidthPhone;
    final bool canAddMoreStyle = viewModel.generatedImages.length < 3;
    // Worst case: 5 card widths (1 original + 4 transformed), 3 gaps in center, paddings
    final double rowReserved = 4 * sectionPadding + lightningWidth + 3 * cardGap;
    final double availableForCards = (screenWidth - rowReserved - overflowSafetyMargin).clamp(0.0, double.infinity);
    final double cardWidth = (availableForCards / 5).clamp(minCardWidth, maxCardWidth);
    final double cardHeight = cardWidth * (180 / 140);

    final Widget originalCard = Padding(
      padding: EdgeInsets.all(sectionPadding),
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
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
          borderRadius: BorderRadius.circular(7),
          child: _originalPhotoBytes != null
              ? Image.memory(
                  _originalPhotoBytes!,
                  fit: BoxFit.cover,
                )
              : const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );

    const double lightningAreaWidth = 60.0;
    final Widget lightningIcon = SizedBox(
      width: lightningAreaWidth,
      child: Center(
        child: Icon(
          CupertinoIcons.bolt_fill,
          size: 36,
          color: Colors.amber.shade400,
        ),
      ),
    );

    final Widget transformedSection = Padding(
      padding: EdgeInsets.all(sectionPadding),
      child: _buildTransformedSection(
        context,
        viewModel,
        appColors,
        cardWidth,
        cardHeight,
        isTablet,
      ),
    );

    final bool isGenerating = viewModel.isGenerating && viewModel.generatedImages.isEmpty;
    final bool isLoadingMore = viewModel.isLoadingMore;
    final bool hasResult = viewModel.generatedImages.isNotEmpty;
    final bool isGeneratingOrLoading = isGenerating || isLoadingMore;
    final String messageBelow = isGeneratingOrLoading
        ? 'Please wait while we create your masterpiece'
        : hasResult
            ? 'Your masterpiece is ready'
            : '';

    final Widget addOneMoreButton = canAddMoreStyle
        ? _buildAddOneMoreStyleButton(context, viewModel)
        : const SizedBox.shrink();

    // Reserve for up to 4 cards (3 images + loading) so no overflow when loading more
    const int maxTransformedCards = 4;
    final double centerSectionWidth = maxTransformedCards * cardWidth +
        (maxTransformedCards - 1) * cardGap +
        2 * sectionPadding;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (messageBelow.isNotEmpty) ...[
          Center(
            child: hasResult
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        messageBelow,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: (!isGeneratingOrLoading && viewModel.hasSelectedImages)
                            ? () {
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.grey.shade600,
                          disabledForegroundColor: Colors.white70,
                        ),
                        child: const Text('Continue'),
                      ),
                    ],
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
          ),
          const SizedBox(height: 24),
        ],
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              originalCard,
              lightningIcon,
              SizedBox(
                width: centerSectionWidth,
                child: Center(
                  child: transformedSection,
                ),
              ),
            ],
          ),
        ),
        if (canAddMoreStyle) ...[
          const SizedBox(height: 24),
          Center(child: addOneMoreButton),
        ],
      ],
    );
  }

  Widget _buildAddOneMoreStyleButton(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
  ) {
    return Material(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: viewModel.isGenerating || viewModel.isLoadingMore
            ? null
            : () async {
                final result = await Navigator.pushNamed(
                  context,
                  AppConstants.kRouteHome,
                  arguments: {
                    'addOneMoreStyle': true,
                    'usedThemeIds': viewModel.generatedImages
                        .map((e) => e.theme.id)
                        .toList(),
                  },
                );
                if (!mounted) return;
                if (result is ThemeModel) {
                  viewModel.tryDifferentStyle(result);
                }
              },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 180,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: const Center(
            child: Text(
              'Add one more style',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransformedSection(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
    double cardWidth,
    double cardHeight,
    bool isTablet,
  ) {
    final isGenerating = viewModel.isGenerating && viewModel.generatedImages.isEmpty;
    final isLoadingMore = viewModel.isLoadingMore;
    final images = viewModel.generatedImages;
    final hasImages = images.isNotEmpty;

    // Initial generation only: single loading card
    if (isGenerating && !hasImages) {
      return Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
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
          borderRadius: BorderRadius.circular(7),
          child: _buildTransformedLoadingPlaceholder(viewModel, appColors),
        ),
      );
    }

    // No images and not generating
    if (!hasImages) {
      return Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
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
          borderRadius: BorderRadius.circular(7),
          child: const Center(
            child: Icon(
              Icons.photo_outlined,
              size: 48,
              color: Colors.white54,
            ),
          ),
        ),
      );
    }

    // One or more images: show all existing + loading card when adding another style
    // Gaps only between cards (not after the last) so row width matches centerSectionWidth
    final imageCards = images
        .map((img) => _buildOneTransformedImageCard(img, cardWidth, cardHeight))
        .toList();
    final Widget? loadingCard = isLoadingMore
        ? Container(
            width: cardWidth,
            height: cardHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
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
              borderRadius: BorderRadius.circular(7),
              child: _buildTransformedLoadingPlaceholder(viewModel, appColors),
            ),
          )
        : null;

    final List<Widget> cardList = [];
    for (int i = 0; i < imageCards.length; i++) {
      cardList.add(imageCards[i]);
      if (i < imageCards.length - 1 || isLoadingMore) {
        cardList.add(const SizedBox(width: 12));
      }
    }
    if (loadingCard != null) cardList.add(loadingCard);

    if (cardList.length == 1) {
      return cardList.first;
    }

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: cardList,
      ),
    );
  }

  Widget _buildOneTransformedImageCard(
    GeneratedImage image,
    double cardWidth,
    double cardHeight,
  ) {
    return Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
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
        borderRadius: BorderRadius.circular(7),
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
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
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
    );
  }

  Widget _buildTransformedLoadingPlaceholder(
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
  ) {
    final message = viewModel.progressMessage.isNotEmpty
        ? viewModel.progressMessage
        : (viewModel.isLoadingMore ? 'Transforming your look...' : 'Creating...');
    return Container(
      color: Colors.black26,
      child: Center(
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
    );
  }

}
