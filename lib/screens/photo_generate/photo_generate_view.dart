import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Orientation;
import 'package:provider/provider.dart';
import 'photo_generate_viewmodel.dart';
import '../photo_capture/photo_model.dart';
import '../theme_selection/theme_model.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_theme.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/theme_card.dart';
import '../../views/widgets/bottom_safe_area.dart';
import '../../services/theme_manager.dart';

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

  void _showThemeSelectionDialog() {
    final themeManager = ThemeManager();
    final themes = themeManager.themes;
    
    if (themes.isEmpty) {
      AppSnackBar.showError(context, 'No themes available');
      return;
    }

    showCupertinoModalPopup(
      context: context,
      builder: (dialogContext) {
        final appColors = AppColors.of(dialogContext);
        
        return Container(
          height: MediaQuery.of(dialogContext).size.height * 0.6,
          decoration: BoxDecoration(
            color: appColors.backgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: CupertinoColors.systemGrey3,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select a Different Theme',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: appColors.textColor,
                      ),
                    ),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: CupertinoColors.systemGrey,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Theme grid - using ThemeCard for consistent image loading
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.7,
                  ),
                  itemCount: themes.length,
                  itemBuilder: (context, index) {
                    final theme = themes[index];
                    final isCurrentTheme = _viewModel.selectedTheme?.id == theme.id;
                    // Check if this theme has already been used for generation
                    final isAlreadyGenerated = _viewModel.generatedImages.any(
                      (img) => img.theme.id == theme.id,
                    );
                    final isDisabled = isCurrentTheme || isAlreadyGenerated;
                    
                    return Stack(
                      children: [
                        // Use ThemeCard for consistent image loading
                        Opacity(
                          opacity: isDisabled ? 0.5 : 1.0,
                          child: ThemeCard(
                            theme: theme,
                            isSelected: isCurrentTheme || isAlreadyGenerated,
                            onTap: isDisabled 
                                ? () {} 
                                : () {
                                    Navigator.pop(dialogContext);
                                    _viewModel.tryDifferentStyle(theme);
                                  },
                          ),
                        ),
                        // Badge for already generated themes
                        if (isAlreadyGenerated)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: CupertinoColors.systemGreen,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                CupertinoIcons.checkmark,
                                color: CupertinoColors.white,
                                size: 12,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCancelConfirmation(BuildContext context) {
    showCupertinoDialog(
      context: context,
      builder: (dialogContext) {
        return CupertinoAlertDialog(
          title: const Text('Cancel Process?'),
          content: const Text(
            'Are you sure you want to cancel? Your generated images will be lost.',
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('No'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(dialogContext);
                // Navigate to terms screen and clear navigation stack
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  AppConstants.kRouteTerms,
                  (route) => false,
                );
              },
              child: const Text('Yes'),
            ),
          ],
        );
      },
    );
  }

  void _showCancelOperationDialog(BuildContext context, PhotoGenerateViewModel viewModel) {
    showCupertinoDialog(
      context: context,
      builder: (dialogContext) {
        return CupertinoAlertDialog(
          title: const Text('Cancel Generation?'),
          content: const Text(
            'An image is currently being generated. Do you want to cancel and go back?',
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Keep Waiting'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(dialogContext);
                // Cancel the current operation
                viewModel.cancelOperation();
                // Navigate to terms screen and clear navigation stack
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  AppConstants.kRouteTerms,
                  (route) => false,
                );
              },
              child: const Text('Cancel & Go Back'),
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
          return CupertinoPageScaffold(
            backgroundColor: appColors.backgroundColor,
            navigationBar: AppTopBar(
              title: 'Generate Photo',
              leading: AppActionButton(
                icon: CupertinoIcons.back,
                onPressed: () {
                  if (viewModel.isOperationInProgress) {
                    _showCancelOperationDialog(context, viewModel);
                  } else {
                    _showCancelConfirmation(context);
                  }
                },
              ),
            ),
            child: SafeArea(
              child: BottomSafePadding(
                child: Column(
                children: [
                  // Step banner
                  _buildStepBanner(context, 2, isLandscape), // 2 = Generate step
                  
                  // Main content: fill height and center block when content is short
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
                  
                  // Bottom buttons
                  _buildBottomButtons(context, viewModel, appColors),
                ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStepBanner(BuildContext context, int currentStep, [bool compact = false]) {
    final appColors = AppColors.of(context);
    
    final steps = [
      _StepInfo(icon: CupertinoIcons.camera, label: 'Photo'),
      _StepInfo(icon: CupertinoIcons.paintbrush, label: 'Select Theme'),
      _StepInfo(icon: CupertinoIcons.sparkles, label: 'Generate'),
      _StepInfo(icon: CupertinoIcons.tray_arrow_down, label: 'Pay & Collect'),
    ];

    final bannerPadding = compact ? const EdgeInsets.symmetric(vertical: 6, horizontal: 6) : const EdgeInsets.symmetric(vertical: 12, horizontal: 8);
    return Container(
      padding: bannerPadding,
      decoration: BoxDecoration(
        color: appColors.backgroundColor,
        boxShadow: [
          BoxShadow(
            color: appColors.shadowColor.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(steps.length, (index) {
          final step = steps[index];
          final isActive = index == currentStep;
          final isCompleted = index < currentStep;
          
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: compact ? 28.0 : 36,
                        height: compact ? 28.0 : 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive 
                              ? CupertinoColors.systemBlue.withValues(alpha: 0.1)
                              : isCompleted
                                  ? CupertinoColors.systemBlue
                                  : Colors.transparent,
                          border: Border.all(
                            color: isActive || isCompleted
                                ? CupertinoColors.systemBlue
                                : CupertinoColors.systemGrey3,
                            width: isActive ? 2 : 1,
                          ),
                        ),
                        child: Icon(
                          isCompleted ? CupertinoIcons.checkmark : step.icon,
                          size: compact ? 14.0 : 18,
                          color: isCompleted
                              ? CupertinoColors.white
                              : isActive
                                  ? CupertinoColors.systemBlue
                                  : CupertinoColors.systemGrey,
                        ),
                      ),
                      SizedBox(height: compact ? 2 : 4),
                      Text(
                        step.label,
                        style: TextStyle(
                          fontSize: compact ? 9 : 10,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                          color: isActive || isCompleted
                              ? CupertinoColors.systemBlue
                              : CupertinoColors.systemGrey,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (index < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 1,
                      margin: EdgeInsets.only(bottom: compact ? 14.0 : 20),
                      color: isCompleted
                          ? CupertinoColors.systemBlue
                          : CupertinoColors.systemGrey3,
                    ),
                  ),
              ],
            ),
          );
        }),
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
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            key: _contentKey,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
            Text(
              'Generating Your Photo',
          style: TextStyle(
            fontSize: isLandscape ? 20 : 24,
            fontWeight: FontWeight.bold,
            color: appColors.textColor,
          ),
        ),
        SizedBox(height: isLandscape ? 4 : 8),
        Text(
          'Please wait while we create your masterpiece',
          style: TextStyle(
            fontSize: isLandscape ? 12 : 14,
            color: appColors.secondaryTextColor,
          ),
        ),
        SizedBox(height: isLandscape ? 12 : 24),
        _buildPhotosDisplay(context, viewModel, appColors, isLandscape),
        if (viewModel.hasError)
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CupertinoColors.systemRed.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.exclamationmark_triangle,
                  color: CupertinoColors.systemRed,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    viewModel.errorMessage!,
                    style: const TextStyle(
                      color: CupertinoColors.systemRed,
                      fontSize: 13,
                    ),
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  onPressed: () => viewModel.clearError(),
                  child: const Icon(
                    CupertinoIcons.xmark,
                    color: CupertinoColors.systemRed,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
            ],
          ),
        ),
      ],
    );

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
            children: [content],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: content,
    );
  }

  Widget _buildPhotosDisplay(BuildContext context, PhotoGenerateViewModel viewModel, AppColors appColors, [bool isLandscape = false]) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > AppConstants.kTabletBreakpoint;

    // Must match _buildGeneratedImageCard exactly (no landscape variant there)
    final double cardWidth = isTablet ? 180.0 : 140.0;
    final double cardHeight = isTablet ? 220.0 : 180.0;

    final double sectionPadding = isLandscape ? 12.0 : 16.0;
    // Fixed header height so original and generated card areas start at same Y (centers align)
    final double headerHeight = isLandscape ? 60.0 : 64.0;
    final Widget originalSection = Padding(
      padding: EdgeInsets.all(sectionPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: headerHeight,
            child: Center(
              child: Text(
                'Original',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: appColors.textColor,
                ),
              ),
            ),
          ),
          Container(
            width: cardWidth,
            height: cardHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: appColors.borderColor),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: _originalPhotoBytes != null
                  ? Image.memory(
                      _originalPhotoBytes!,
                      fit: BoxFit.cover,
                    )
                  : Center(
                      child: CupertinoActivityIndicator(
                        color: appColors.textColor,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
    
    final Widget generatedSection = _buildGeneratedImagesSection(context, viewModel, appColors, isTablet, isLandscape, headerHeight);
    
    if (isLandscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          originalSection,
          const SizedBox(width: 16),
          Expanded(child: generatedSection),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        originalSection,
        const SizedBox(height: 24),
        generatedSection,
      ],
    );
  }

  Widget _buildGeneratedImagesSection(BuildContext context, PhotoGenerateViewModel viewModel, AppColors appColors, bool isTablet, [bool isLandscape = false, double headerHeight = 64.0]) {
    final cardWidth = isLandscape ? 100.0 : (isTablet ? 180.0 : 140.0);
    final cardHeight = isLandscape ? 130.0 : (isTablet ? 220.0 : 180.0);

    final Widget headerContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Generated Images',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: appColors.textColor,
              ),
            ),
            if (viewModel.generatedImages.length > 1) ...[
              const SizedBox(width: 16),
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                onPressed: () {
                  if (viewModel.selectedCount == viewModel.generatedImages.length) {
                    viewModel.deselectAllImages();
                    if (viewModel.generatedImages.isNotEmpty) {
                      viewModel.toggleImageSelection(viewModel.generatedImages.first.id);
                    }
                  } else {
                    viewModel.selectAllImages();
                  }
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      viewModel.selectedCount == viewModel.generatedImages.length
                          ? CupertinoIcons.checkmark_square
                          : CupertinoIcons.square,
                      size: 16,
                      color: CupertinoColors.systemBlue,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      viewModel.selectedCount == viewModel.generatedImages.length
                          ? 'Deselect'
                          : 'Select All',
                      style: const TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.systemBlue,
                      ),
                    ),
                  ],
                ),
              ),
              if (viewModel.generatedImages.isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(
                  '${viewModel.selectedCount} of ${viewModel.generatedImages.length} selected (tap to select/deselect)',
                  style: TextStyle(
                    fontSize: 12,
                    color: appColors.secondaryTextColor,
                  ),
                ),
              ],
            ],
          ],
        ),
        const SizedBox(height: 12),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          height: headerHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [headerContent],
          ),
        ),
        if (viewModel.isGenerating && viewModel.generatedImages.isEmpty)
          // Initial generation - show loading state
          _buildGeneratingPlaceholder(viewModel, appColors, isTablet)
        else if (viewModel.generatedImages.isEmpty)
          // No images yet
          Container(
            width: cardWidth,
            height: cardHeight,
            decoration: BoxDecoration(
              color: appColors.surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: appColors.borderColor),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.photo,
                    size: 48,
                    color: appColors.secondaryTextColor,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No images yet',
                    style: TextStyle(
                      color: appColors.secondaryTextColor,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          // Show generated images in a grid layout
          Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: [
              ...viewModel.generatedImages.map((image) => 
                _buildGeneratedImageCard(context, image, viewModel, appColors, isTablet),
              ),
              // Loading more indicator
              if (viewModel.isLoadingMore)
                _buildGeneratingPlaceholder(viewModel, appColors, isTablet),
            ],
          ),
      ],
    );
  }

  Widget _buildGeneratedImageCard(BuildContext context, GeneratedImage image, PhotoGenerateViewModel viewModel, AppColors appColors, bool isTablet) {
    final cardWidth = isTablet ? 180.0 : 140.0;
    final cardHeight = isTablet ? 220.0 : 180.0;
    
    return GestureDetector(
      onTap: () => viewModel.toggleImageSelection(image.id),
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: image.isSelected 
                ? CupertinoColors.systemBlue 
                : appColors.borderColor,
            width: image.isSelected ? 3 : 1,
          ),
          boxShadow: image.isSelected ? [
            BoxShadow(
              color: CupertinoColors.systemBlue.withValues(alpha: 0.3),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ] : null,
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(image.isSelected ? 9 : 11),
              child: Image.network(
                image.imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CupertinoActivityIndicator(
                      color: appColors.textColor,
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Center(
                  child: Icon(
                    CupertinoIcons.exclamationmark_triangle,
                    color: appColors.errorColor,
                  ),
                ),
              ),
            ),
            // Selection indicator
            if (image.isSelected)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: CupertinoColors.systemBlue,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    CupertinoIcons.checkmark,
                    color: CupertinoColors.white,
                    size: 16,
                  ),
                ),
              ),
            // Theme name badge
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
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(11),
                  ),
                ),
                child: Text(
                  image.theme.name,
                  style: const TextStyle(
                    color: CupertinoColors.white,
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

  Widget _buildGeneratingPlaceholder(PhotoGenerateViewModel viewModel, AppColors appColors, bool isTablet) {
    final cardWidth = isTablet ? 180.0 : 140.0;
    final cardHeight = isTablet ? 260.0 : 220.0; // Increased height for cancel button
    final isTakingLong = viewModel.elapsedSeconds > 60;
    
    return Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        color: appColors.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTakingLong ? CupertinoColors.systemOrange : appColors.borderColor,
          width: isTakingLong ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CupertinoActivityIndicator(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              viewModel.progressMessage.isNotEmpty 
                  ? viewModel.progressMessage 
                  : 'Transforming your look...',
              style: TextStyle(
                fontSize: 11,
                color: appColors.secondaryTextColor,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${viewModel.elapsedSeconds}s',
            style: TextStyle(
              fontSize: 11,
              fontWeight: isTakingLong ? FontWeight.bold : FontWeight.normal,
              color: isTakingLong ? CupertinoColors.systemOrange : appColors.secondaryTextColor,
            ),
          ),
          // Progress bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            height: 4,
            decoration: BoxDecoration(
              color: appColors.borderColor,
              borderRadius: BorderRadius.circular(2),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Animate progress based on elapsed time (assume ~120s max)
                final progress = (viewModel.elapsedSeconds / 120).clamp(0.0, 0.95);
                return Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    width: constraints.maxWidth * progress,
                    decoration: BoxDecoration(
                      color: isTakingLong ? CupertinoColors.systemOrange : CupertinoColors.systemBlue,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              },
            ),
          ),
          // Warning message when taking too long
          if (isTakingLong) ...[
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Taking longer than expected',
                style: TextStyle(
                  fontSize: 9,
                  color: CupertinoColors.systemOrange,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 8),
          // Cancel button
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: Size.zero,
            onPressed: () => _showCancelOperationDialog(context, viewModel),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 11,
                color: CupertinoColors.systemRed,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons(BuildContext context, PhotoGenerateViewModel viewModel, AppColors appColors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appColors.backgroundColor,
        boxShadow: [
          BoxShadow(
            color: appColors.shadowColor.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Try Different Style button
          Expanded(
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 14),
              color: viewModel.canTryDifferentStyle
                  ? appColors.surfaceColor
                  : CupertinoColors.systemGrey5,
              borderRadius: BorderRadius.circular(12),
              onPressed: viewModel.canTryDifferentStyle
                  ? () => _showThemeSelectionDialog()
                  : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.arrow_2_circlepath,
                    size: 18,
                    color: viewModel.canTryDifferentStyle
                        ? appColors.textColor
                        : CupertinoColors.systemGrey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Try Different Style',
                    style: TextStyle(
                      fontSize: 13,
                      color: viewModel.canTryDifferentStyle
                          ? appColors.textColor
                          : CupertinoColors.systemGrey,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Continue button - passes only selected images
          Expanded(
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 14),
              color: viewModel.hasSelectedImages
                  ? CupertinoColors.systemBlue
                  : CupertinoColors.systemGrey3,
              borderRadius: BorderRadius.circular(12),
              onPressed: viewModel.hasSelectedImages && 
                         !viewModel.isGenerating && 
                         !viewModel.isLoadingMore
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    CupertinoIcons.arrow_right,
                    size: 18,
                    color: CupertinoColors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: viewModel.hasSelectedImages
                          ? CupertinoColors.white
                          : appColors.secondaryTextColor,
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
}

/// Helper class to store step information
class _StepInfo {
  final IconData icon;
  final String label;

  _StepInfo({required this.icon, required this.label});
}
