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
  final TextEditingController _kioskNameController = TextEditingController();
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
    _kioskNameController.addListener(() {
      _viewModel.updateKioskName(_kioskNameController.text);
    });
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
    _kioskNameController.dispose();
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
          if (!mounted) return null;
          try {
            if (cachedFile != null) {
              return await precacheImage(FileImage(cachedFile), context);
            } else {
              return await precacheImage(NetworkImage(url), context);
            }
          } catch (e) {
            // Precache failure is not critical
            debugPrint('Precache failed for carousel image $url: $e');
            return null;
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
    final kioskCode = _kioskNameController.text.trim();
    
    // Call the new API endpoint
    final success = await _viewModel.acceptTermsAndCreateSession(kioskCode);
    
    if (success && mounted) {
      // Navigate to Select Theme screen on success
      Navigator.pushReplacementNamed(context, AppConstants.kRouteHome);
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

    // Adjust spacing based on device type and available height
    final double logoSpacing = isTablet ? 12.0 : 8.0;
    final double carouselSpacing = isTablet ? 16.0 : 12.0;
    final double taglineSpacing = isTablet ? 16.0 : 12.0;
    final double actionButtonsSpacing = isTablet ? 20.0 : 16.0;
    final double kioskFieldSpacing = isTablet ? 16.0 : 12.0;
    final double checkboxSpacing = isTablet ? 16.0 : 12.0;
    final double buttonSpacing = isTablet ? 12.0 : 8.0;

    // Adjust carousel height based on available space - increased size
    final double carouselHeight = isTablet
        ? (availableHeight * 0.30).clamp(250.0, 350.0)
        : (availableHeight * 0.28).clamp(180.0, 250.0);

    // Adjust logo size - tripled for better visibility
    final double logoSize = isTablet ? 240.0 : 180.0;
    final double logoIconSize = isTablet ? 40.0 : 30.0;

    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: CupertinoPageScaffold(
        backgroundColor: CupertinoColors.white,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isTablet ? 32.0 : 16.0,
                      vertical: isTablet ? 16.0 : 8.0,
                    ),
                    child: Consumer<TermsAndConditionsViewModel>(
                      builder: (context, viewModel, child) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Logo Section
                            _buildLogo(logoSize, logoIconSize),
                            SizedBox(height: logoSpacing),
                            // Image Carousel
                            _buildImageCarousel(isTablet, carouselHeight),
                            SizedBox(height: carouselSpacing),
                            // Tagline
                            Text(
                              'Snap. Transform. Take Home Magic.',
                              style: TextStyle(
                                fontSize: isTablet ? 18.0 : 14.0,
                                color: CupertinoColors.systemGrey,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: taglineSpacing),
                            // Action Buttons
                            _buildActionButtons(isTablet),
                            SizedBox(height: actionButtonsSpacing),
                            // KIOSK Name Field
                            _buildKioskNameField(isTablet),
                            SizedBox(height: kioskFieldSpacing),
                            // Checkbox
                            _buildCheckbox(viewModel, isTablet),
                            SizedBox(height: checkboxSpacing),
                            // Start Your Experience Button
                            _buildStartButton(viewModel, isTablet),
                            SizedBox(height: buttonSpacing),
                            // Privacy Note
                            _buildPrivacyNote(isTablet),
                            // Add bottom padding to ensure content is above system bar
                            SizedBox(
                                height: MediaQuery.of(context).padding.bottom),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
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
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
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
                      color: CupertinoColors.systemBackground,
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
              );
            },
          ),
        ),
        const SizedBox(height: 8),
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

  Widget _buildKioskNameField(bool isTablet) {
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.tertiarySystemFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: CupertinoTextField(
        controller: _kioskNameController,
        placeholder: 'Enter KIOSK name',
        padding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: isTablet ? 14 : 10,
        ),
        style: TextStyle(fontSize: isTablet ? 16 : 14),
        textCapitalization: TextCapitalization.words,
        decoration: const BoxDecoration(),
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
