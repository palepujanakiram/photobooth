import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'terms_and_conditions_viewmodel.dart';
import '../../utils/constants.dart';
import '../../utils/app_config.dart';
import '../../services/theme_manager.dart';
import '../../services/image_cache_service.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/cached_network_image.dart';
import '../../views/widgets/full_screen_loader.dart';
import '../../views/widgets/app_colors.dart';
import 'webview_screen.dart';

class TermsAndConditionsScreen extends StatefulWidget {
  final List<String>? carouselImages;

  const TermsAndConditionsScreen({
    super.key,
    this.carouselImages,
  });

  @override
  State<TermsAndConditionsScreen> createState() =>
      _TermsAndConditionsScreenState();
}

class _TermsAndConditionsScreenState extends State<TermsAndConditionsScreen> {
  late TermsAndConditionsViewModel _viewModel;
  final PageController _pageController = PageController();
  final ThemeManager _themeManager = ThemeManager();
  final ImageCacheService _imageCacheService = ImageCacheService();
  int _currentPage = 0;
  Timer? _carouselTimer;
  List<String> _carouselImages = [];
  bool _isFirstImageLoaded = false;
  bool _areAllImagesLoaded = false;

  @override
  void initState() {
    super.initState();
    _viewModel = TermsAndConditionsViewModel();
    // Initialize carousel images
    _initializeCarouselImages();
    // Preload images (first first, then rest)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadCarouselImages();
    });
  }

  /// Initializes carousel images from provided parameter or ThemeManager
  void _initializeCarouselImages() {
    if (widget.carouselImages != null && widget.carouselImages!.isNotEmpty) {
      // Use provided images from slideshow
      _carouselImages = widget.carouselImages!;
    } else {
      // Try to get images from ThemeManager
      _carouselImages = _themeManager.getSampleImageUrls();
      // If no images from ThemeManager, use default fallback
      if (_carouselImages.isEmpty) {
        _carouselImages = [
          'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?w=800&h=600&fit=crop',
          'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=800&h=600&fit=crop',
          'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=800&h=600&fit=crop',
          'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=800&h=600&fit=crop',
        ];
      }
    }
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _pageController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  /// Preloads carousel images: first image first, then rest
  Future<void> _preloadCarouselImages() async {
    if (_carouselImages.isEmpty) return;

    // Step 1: Cache and load first image immediately
    if (_carouselImages.isNotEmpty) {
      try {
        // Cache the first image
        final cachedFile =
            await _imageCacheService.cacheImage(_carouselImages[0]).timeout(
                  const Duration(seconds: 10),
                  onTimeout: () => null,
                );

        // Precache for immediate display
        // Use context directly after checking mounted (StatefulWidget context is safe)
        if (mounted) {
          try {
            if (cachedFile != null) {
              await precacheImage(FileImage(cachedFile), context).timeout(
                const Duration(seconds: 10),
                onTimeout: () {},
              );
            } else {
              await precacheImage(NetworkImage(_carouselImages[0]), context)
                  .timeout(
                const Duration(seconds: 10),
                onTimeout: () {},
              );
            }
          } catch (e) {
            // Precache failure is not critical
            debugPrint('Precache failed for first carousel image: $e');
          }

          setState(() {
            _isFirstImageLoaded = true;
          });
        }
      } catch (e) {
        // Continue anyway - image might still load when displayed
        if (mounted) {
          setState(() {
            _isFirstImageLoaded = true;
          });
        }
      }
    }

    // Step 2: Cache and preload remaining images in parallel
    if (_carouselImages.length > 1) {
      final remainingUrls = _carouselImages.sublist(1);
      try {
        final preloadFutures = remainingUrls.map((url) async {
          // Cache the image first
          final cachedFile = await _imageCacheService.cacheImage(url).timeout(
                const Duration(seconds: 10),
                onTimeout: () => null,
              );

          // Precache for immediate display
          // Use context directly after checking mounted (StatefulWidget context is safe)
          // Note: We're in a StatefulWidget, so we can check mounted and use context
          if (!mounted) return;
          try {
            if (cachedFile != null) {
              await precacheImage(FileImage(cachedFile), context);
            } else {
              await precacheImage(NetworkImage(url), context);
            }
          } catch (e) {
            // Precache failure is not critical
            debugPrint('Precache failed for carousel image $url: $e');
          }
        }).toList();

        await Future.wait(preloadFutures);
      } catch (e) {
        // Continue anyway
      }
    }

    // Step 3: Start auto-scroll once all images are loaded
    if (mounted) {
      setState(() {
        _areAllImagesLoaded = true;
      });
      _startCarouselAutoScroll();
    }
  }

  void _startCarouselAutoScroll() {
    if (_carouselImages.isEmpty || !_areAllImagesLoaded) return;

    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final nextPage = (_currentPage + 1) % _carouselImages.length;
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _openTermsLink() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (context) => const WebViewScreen(
          url: AppConfig.termsAndConditionsUrl,
          title: 'Terms and Conditions',
        ),
      ),
    );
  }

  Future<void> _handleAccept() async {
    // Call the new API endpoint (kiosk code is optional, passing null)
    final success = await _viewModel.acceptTermsAndCreateSession(null);

    if (success && mounted) {
      // Navigate to Select Camera screen on success
      Navigator.pushReplacementNamed(
          context, AppConstants.kRouteCameraSelection);
    } else if (mounted && _viewModel.hasError) {
      // Show error snackbar on failure
      AppSnackBar.showError(
        context,
        _viewModel.errorMessage ?? 'Failed to accept terms',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    // Calculate scale factor based on screen width (normalize to a base width of 400px)
    // This provides smooth scaling across all device sizes
    final double scaleFactor = (screenWidth / 400.0).clamp(0.8, 2.0);

    // Calculate dynamic spacing that scales with screen size (minimal for better fit)
    final double carouselSpacing = 1.0 + (scaleFactor * 0.2);
    final double taglineSpacing = 1.0 + (scaleFactor * 0.2);
    final double actionButtonsSpacing = 1.5 + (scaleFactor * 0.2);
    final double checkboxSpacing = 1.0 + (scaleFactor * 0.2);
    final double buttonSpacing = 1.0 + (scaleFactor * 0.2);

    // Calculate font sizes that scale with screen size
    final double taglineFontSize = 12.0 + (scaleFactor * 3.0);

    // Calculate horizontal padding for bottom content
    final horizontalPadding = 8.0 + (scaleFactor * 8.0);
    
    // Calculate screen dimensions
    final screenHeight = MediaQuery.of(context).size.height;
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Carousel images as full screen background (ignoring safe areas)
          Positioned.fill(
            child: _buildImageCarousel(screenHeight),
          ),
          // Bottom controls positioned at bottom of screen
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              color: AppColors.of(context).backgroundColor,
              padding: EdgeInsets.only(
                left: horizontalPadding,
                right: horizontalPadding,
                top: 16,
                bottom: bottomPadding,
              ),
              child: Consumer<TermsAndConditionsViewModel>(
                builder: (context, viewModel, child) {
                  return SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(height: carouselSpacing + 8), // Increased top padding
                        // Tagline
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Snap. Transform. Take Home Magic.',
                            style: TextStyle(
                              fontSize: taglineFontSize,
                              color: CupertinoColors.systemGrey,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        SizedBox(height: taglineSpacing + 8), // Increased bottom padding
                        // Action Buttons
                        _buildActionButtons(scaleFactor),
                        SizedBox(height: actionButtonsSpacing),
                        // Checkbox with extra padding below
                        _buildCheckbox(viewModel, scaleFactor),
                        SizedBox(height: checkboxSpacing + 4),
                        // Start Your Experience Button
                        _buildStartButton(viewModel, scaleFactor),
                        SizedBox(height: buttonSpacing * 0.5), // Reduced spacing
                        // Privacy Note
                        _buildPrivacyNote(scaleFactor),
                        SizedBox(height: 4), // Minimal bottom padding
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          // ZenAI Logo overlay on top of carousel
          Positioned(
            top: statusBarHeight + 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                color: Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _buildNavBarLogo(context),
              ),
            ),
          ),
          // Full screen loader overlay - positioned to cover entire screen
          Consumer<TermsAndConditionsViewModel>(
            builder: (context, viewModel, child) {
              if (viewModel.isSubmitting) {
                return const Positioned.fill(
                  child: FullScreenLoader(
                    text: 'Creating Session',
                    loaderColor: CupertinoColors.systemBlue,
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavBarLogo(BuildContext context) {
    final appColors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.transparent,
      ),
      child: Image.asset(
        'lib/images/zen_ai_logo.jpeg',
        height: 60,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          // Fallback to text if image fails to load
          return Text(
            'Zen AI',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: appColors.textColor,
              shadows: [
                Shadow(
                  offset: const Offset(0, 2),
                  blurRadius: 4,
                  color: appColors.shadowColor,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildImageCarousel(double height) {
    if (_carouselImages.isEmpty) {
      return const SizedBox.shrink();
    }

    // Show loading indicator while first image is loading
    if (!_isFirstImageLoaded) {
      return SizedBox(
        height: height,
        child: const Center(
          child: CupertinoActivityIndicator(),
        ),
      );
    }

    // PageView uses full height since dots are hidden
    return SizedBox(
      height: height,
      child: PageView.builder(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _currentPage = index;
          });
          // Reset timer when page changes manually (only if all images loaded)
          if (_areAllImagesLoaded) {
            _startCarouselAutoScroll();
          }
        },
        itemCount: _carouselImages.length,
        itemBuilder: (context, index) {
          return ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 1.0,
              child: CachedNetworkImage(
                imageUrl: _carouselImages[index],
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
                placeholder: Builder(
                  builder: (context) => Container(
                    color: AppColors.of(context).backgroundColor,
                    child: const Center(
                      child: CupertinoActivityIndicator(),
                    ),
                  ),
                ),
                errorWidget: Builder(
                  builder: (context) => Container(
                    color: AppColors.of(context).backgroundColor,
                    child: const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.photo,
                            size: 48,
                            color: CupertinoColors.systemGrey2,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Image unavailable',
                            style: TextStyle(
                              color: CupertinoColors.systemGrey,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildActionButtons(double scaleFactor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionButton(
          icon: CupertinoIcons.camera,
          label: 'Take Photo',
          scaleFactor: scaleFactor,
        ),
        _buildActionButton(
          icon: CupertinoIcons.star_fill,
          label: 'AI Transform',
          scaleFactor: scaleFactor,
        ),
        _buildActionButton(
          icon: CupertinoIcons.printer_fill,
          label: 'Print & Keep',
          scaleFactor: scaleFactor,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required double scaleFactor,
  }) {
    final double iconSize = 20.0 + (scaleFactor * 4.0);
    final double fontSize = 8.0 + (scaleFactor * 2.0);
    final double horizontalPadding = 6.0 + (scaleFactor * 3.0);
    final double verticalPadding = 12.0 + (scaleFactor * 2.0);

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: verticalPadding,
        ),
        decoration: BoxDecoration(
          color: CupertinoColors.systemBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: iconSize,
              color: CupertinoColors.systemBlue,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                color: CupertinoColors.systemBlue,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckbox(
      TermsAndConditionsViewModel viewModel, double scaleFactor) {
    final double checkboxSize = 20.0 + (scaleFactor * 4.0);
    final double fontSize = 10.0 + (scaleFactor * 2.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            viewModel.toggleAgreement(!viewModel.isAgreed);
          },
          child: Container(
            width: checkboxSize,
            height: checkboxSize,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: viewModel.isAgreed
                    ? CupertinoColors.systemBlue
                    : CupertinoColors.systemGrey,
                width: 2.5,
              ),
              color: viewModel.isAgreed
                  ? CupertinoColors.systemBlue
                  : CupertinoColors.systemBackground,
            ),
            child: viewModel.isAgreed
                ? Builder(
                    builder: (context) => Icon(
                      CupertinoIcons.checkmark,
                      color: AppColors.of(context).textColor,
                      size: checkboxSize * 0.65,
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () {
              viewModel.toggleAgreement(!viewModel.isAgreed);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 4.0),
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: fontSize,
                    color: CupertinoColors.systemGrey,
                    height: 1.3,
                  ),
                  children: [
                    const TextSpan(
                      text: 'I have read and agree to the ',
                    ),
                    TextSpan(
                      text: 'Terms & Conditions',
                      style: TextStyle(
                        fontSize: fontSize,
                        color: CupertinoColors.systemBlue,
                        decoration: TextDecoration.underline,
                        fontWeight: FontWeight.w500,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          _openTermsLink();
                        },
                    ),
                    const TextSpan(
                      text: ' and consent to AI processing of my photo',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStartButton(
      TermsAndConditionsViewModel viewModel, double scaleFactor) {
    final double buttonHeight = 50.0 + (scaleFactor * 8.0);
    final double fontSize = 14.0 + (scaleFactor * 2.0);

    return SizedBox(
      width: double.infinity,
      height: buttonHeight,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        color: viewModel.canSubmit
            ? CupertinoColors.systemBlue
            : CupertinoColors.systemGrey3,
        borderRadius: BorderRadius.circular(12),
        onPressed: viewModel.canSubmit ? _handleAccept : null,
        child: viewModel.isSubmitting
            ? const CupertinoActivityIndicator(
                color: CupertinoColors.white,
              )
            : Text(
                'Start Your Experience',
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.bold,
                  color: AppColors.of(context).buttonTextColor,
                ),
              ),
      ),
    );
  }

  Widget _buildPrivacyNote(double scaleFactor) {
    final double iconSize = 10.0 + (scaleFactor * 2.0);
    final double fontSize = 8.0 + (scaleFactor * 1.5);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          CupertinoIcons.time,
          size: iconSize,
          color: CupertinoColors.systemGrey,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'Sessions auto-delete after 24 hours for your privacy',
            style: TextStyle(
              fontSize: fontSize,
              color: CupertinoColors.systemGrey,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
