import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:provider/provider.dart';
import 'photo_generate_viewmodel.dart';
import '../photo_capture/photo_model.dart';
import '../theme_selection/theme_model.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_theme.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/theme_card.dart';
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
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);

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
              child: Column(
                children: [
                  // Step banner
                  _buildStepBanner(context, 2), // 2 = Generate step
                  
                  // Main content
                  Expanded(
                    child: _buildMainContent(context, viewModel, appColors),
                  ),
                  
                  // Bottom buttons
                  _buildBottomButtons(context, viewModel, appColors),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStepBanner(BuildContext context, int currentStep) {
    final appColors = AppColors.of(context);
    
    final steps = [
      _StepInfo(icon: CupertinoIcons.camera, label: 'Photo'),
      _StepInfo(icon: CupertinoIcons.paintbrush, label: 'Select Theme'),
      _StepInfo(icon: CupertinoIcons.sparkles, label: 'Generate'),
      _StepInfo(icon: CupertinoIcons.tray_arrow_down, label: 'Pay & Collect'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
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
                        width: 36,
                        height: 36,
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
                          size: 18,
                          color: isCompleted
                              ? CupertinoColors.white
                              : isActive
                                  ? CupertinoColors.systemBlue
                                  : CupertinoColors.systemGrey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step.label,
                        style: TextStyle(
                          fontSize: 10,
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
                      margin: const EdgeInsets.only(bottom: 20),
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

  Widget _buildMainContent(BuildContext context, PhotoGenerateViewModel viewModel, AppColors appColors) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Title
          Text(
            'Generating Your Photo',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: appColors.textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please wait while we create your masterpiece',
            style: TextStyle(
              fontSize: 14,
              color: appColors.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 24),
          
          // Photos display
          _buildPhotosDisplay(context, viewModel, appColors),
          
          // Error message
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
                    minSize: 0,
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
    );
  }

  Widget _buildPhotosDisplay(BuildContext context, PhotoGenerateViewModel viewModel, AppColors appColors) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > AppConstants.kTabletBreakpoint;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Original photo
        Column(
          children: [
            Text(
              'Original',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: appColors.secondaryTextColor,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: isTablet ? 150 : 120,
              height: isTablet ? 200 : 150,
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
        
        const SizedBox(height: 24),
        
        // Generated images section
        _buildGeneratedImagesSection(context, viewModel, appColors, isTablet),
      ],
    );
  }

  Widget _buildGeneratedImagesSection(BuildContext context, PhotoGenerateViewModel viewModel, AppColors appColors, bool isTablet) {
    final cardWidth = isTablet ? 180.0 : 140.0;
    final cardHeight = isTablet ? 220.0 : 180.0;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Label with selection controls
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
              // Select All / Deselect toggle
              CupertinoButton(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minSize: 0,
                onPressed: () {
                  if (viewModel.selectedCount == viewModel.generatedImages.length) {
                    // All selected - deselect all except first
                    viewModel.deselectAllImages();
                    // Re-select first one to maintain at least one selected
                    if (viewModel.generatedImages.isNotEmpty) {
                      viewModel.toggleImageSelection(viewModel.generatedImages.first.id);
                    }
                  } else {
                    // Not all selected - select all
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
            ],
          ],
        ),
        // Selection hint
        if (viewModel.generatedImages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${viewModel.selectedCount} of ${viewModel.generatedImages.length} selected (tap to select/deselect)',
              style: TextStyle(
                fontSize: 11,
                color: appColors.secondaryTextColor,
              ),
            ),
          ),
        const SizedBox(height: 12),
        
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
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
            minSize: 0,
            onPressed: () => _showCancelOperationDialog(context, viewModel),
            child: Text(
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
