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
        final cachedFile = await _imageCacheService.cacheImage(_carouselImages[0]).timeout(
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
              await precacheImage(NetworkImage(_carouselImages[0]), context).timeout(
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
      Navigator.pushReplacementNamed(context, AppConstants.kRouteCameraSelection);
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
    final screenHeight = MediaQuery.of(context).size.height;
    final isTablet = screenWidth > AppConstants.kTabletBreakpoint;

    // Calculate responsive spacing based on screen height
    final availableHeight = screenHeight -
        MediaQuery.of(context).padding.top -
        MediaQuery.of(context).padding.bottom;

    // Adjust logo size dynamically based on available height
    // Reduced size to fit all content without scrolling
    final double logoSize = isTablet 
        ? (availableHeight * 0.15).clamp(150.0, 220.0)
        : (availableHeight * 0.12).clamp(100.0, 160.0);
    final double logoIconSize = logoSize * 0.18;

    // Calculate carousel height dynamically based on available space
    // Reserve space for other elements (logo, buttons, etc.)
    final double reservedSpace = isTablet 
        ? (logoSize * 1.2 + 180) // Logo + buttons + spacing
        : (logoSize * 1.2 + 160); // Logo + buttons + spacing
    final double carouselHeight = (availableHeight - reservedSpace).clamp(120.0, availableHeight * 0.30);

    // Calculate dynamic spacing based on available height to prevent overflow
    // Reduced spacing to fit all content without scrolling
    final double logoSpacing = availableHeight * 0.008;
    final double carouselSpacing = availableHeight * 0.010;
    final double taglineSpacing = availableHeight * 0.008;
    final double actionButtonsSpacing = availableHeight * 0.010;
    final double checkboxSpacing = availableHeight * 0.008;
    final double buttonSpacing = availableHeight * 0.008;

    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Container(
        color: CupertinoColors.white, // Ensure Stack background is white
        child: Stack(
          children: [
            CupertinoPageScaffold(
              backgroundColor: CupertinoColors.white,
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final content = Container(
                      color: CupertinoColors.white, // Ensure content background is white
                      child: Padding(
                        padding: EdgeInsets.only(
                          left: isTablet ? 32.0 : 16.0,
                          right: isTablet ? 32.0 : 16.0,
                          top: isTablet ? 4.0 : 4.0, // Reduced top padding
                          bottom: isTablet ? 8.0 : 4.0,
                        ),
                        child: Consumer<TermsAndConditionsViewModel>(
                          builder: (context, viewModel, child) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Flexible spacer above logo to push content down (only for tablets)
                                // Use SizedBox with calculated height instead of Spacer to avoid unbounded constraints
                                if (isTablet) SizedBox(height: availableHeight * 0.05),
                                // Logo Section - sized dynamically
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: _buildLogo(logoSize, logoIconSize),
                                ),
                                SizedBox(height: logoSpacing),
                                // Image Carousel - sized dynamically, constrained to prevent overflow
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: carouselHeight,
                                  ),
                                  child: _buildImageCarousel(isTablet, carouselHeight),
                                ),
                                SizedBox(height: carouselSpacing),
                                // Tagline
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'Snap. Transform. Take Home Magic.',
                                    style: TextStyle(
                                      fontSize: isTablet ? 18.0 : 14.0,
                                      color: CupertinoColors.systemGrey,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                SizedBox(height: taglineSpacing),
                                // Action Buttons
                                _buildActionButtons(isTablet),
                                SizedBox(height: actionButtonsSpacing),
                                // Checkbox
                                _buildCheckbox(viewModel, isTablet),
                                SizedBox(height: checkboxSpacing),
                                // Start Your Experience Button
                                _buildStartButton(viewModel, isTablet),
                                SizedBox(height: buttonSpacing),
                                // Privacy Note
                                _buildPrivacyNote(isTablet),
                                // Add bottom padding to ensure content is above system bar
                                SizedBox(height: MediaQuery.of(context).padding.bottom),
                              ],
                            );
                          },
                        ),
                      ),
                    );

                    // No scrolling - content should fit within available space
                    return SizedBox(
                      height: constraints.maxHeight,
                      child: content,
                    );
                  },
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
      ),
    );
  }

  Widget _buildLogo(double logoSize, double iconSize) {
    return Image.asset(
      'lib/images/zen_ai_logo.jpeg',
      height: logoSize * 1.2,
      width: logoSize * 1.2,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        // Fallback to text if image fails to load
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Zen AI',
              style: TextStyle(
                fontSize: logoSize * 0.35,
                fontWeight: FontWeight.bold,
                color: CupertinoColors.systemBlue,
              ),
            ),
            Text(
              'PHOTO BOOTH',
              style: TextStyle(
                fontSize: logoSize * 0.15,
                color: CupertinoColors.systemGrey,
                letterSpacing: 2,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildImageCarousel(bool isTablet, double height) {
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

    // Calculate available height for PageView (reserve space for dots indicator)
    // Total space needed: PageView + spacing (4px) + dots (6px) = height
    // So: pageViewHeight = height - 4 - 6 = height - 10
    const double spacingHeight = 4.0; // Spacing between PageView and dots
    const double dotsHeight = 6.0; // Height of dots indicator
    final double pageViewHeight = (height - spacingHeight - dotsHeight).clamp(100.0, height - 10);
    
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: height,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: pageViewHeight,
            child: Container(
              color: Colors.transparent, // Make PageView container transparent
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
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: const BoxDecoration(
                      color: Colors.transparent, // Make background transparent
                    ),
                    child: CachedNetworkImage(
                      imageUrl: _carouselImages[index],
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.contain,
                      placeholder: Container(
                        color: Colors.transparent,
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: Colors.blue,
                          ),
                        ),
                      ),
                      errorWidget: Container(
                        color: Colors.transparent, // Make error widget background transparent too
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
                  );
                },
              ),
            ),
          ),
          SizedBox(height: spacingHeight), // spacingHeight is not const, so SizedBox cannot be const
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_carouselImages.length, (index) {
              return Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentPage == index
                      ? CupertinoColors.systemBlue
                      : CupertinoColors.systemGrey3,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isTablet) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionButton(
          icon: CupertinoIcons.camera,
          label: 'Take Photo',
          isTablet: isTablet,
        ),
        _buildActionButton(
          icon: CupertinoIcons.star_fill,
          label: 'AI Transform',
          isTablet: isTablet,
        ),
        _buildActionButton(
          icon: CupertinoIcons.printer_fill,
          label: 'Print & Keep',
          isTablet: isTablet,
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isTablet,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 12.0 : 8.0,
          vertical: isTablet ? 16.0 : 14.0,
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
              size: isTablet ? 28 : 24,
              color: CupertinoColors.systemBlue,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: isTablet ? 12 : 10,
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

  Widget _buildCheckbox(TermsAndConditionsViewModel viewModel, bool isTablet) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () {
            viewModel.toggleAgreement(!viewModel.isAgreed);
          },
          child: Container(
            width: isTablet ? 28 : 24,
            height: isTablet ? 28 : 24,
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
                ? const Icon(
                    CupertinoIcons.checkmark,
                    color: CupertinoColors.white,
                    size: 18,
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
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: isTablet ? 14 : 12,
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
                      fontSize: isTablet ? 14 : 12,
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
      ],
    );
  }

  Widget _buildStartButton(
      TermsAndConditionsViewModel viewModel, bool isTablet) {
    return SizedBox(
      width: double.infinity,
      height: isTablet ? 64.0 : 58.0,
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
                  fontSize: isTablet ? 18.0 : 16.0,
                  fontWeight: FontWeight.bold,
                  color: CupertinoColors.white,
                ),
              ),
      ),
    );
  }

  Widget _buildPrivacyNote(bool isTablet) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          CupertinoIcons.time,
          size: isTablet ? 14 : 12,
          color: CupertinoColors.systemGrey,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'Sessions auto-delete after 24 hours for your privacy',
            style: TextStyle(
              fontSize: isTablet ? 11 : 10,
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
