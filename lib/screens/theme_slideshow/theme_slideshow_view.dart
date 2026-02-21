import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_slideshow_viewmodel.dart';
import '../terms_and_conditions/terms_and_conditions_view.dart';
import '../../utils/constants.dart';
import '../../views/widgets/cached_network_image.dart';

/// Enum for different slide transition types
enum SlideTransitionType {
  fade,
  slideLeft,
  slideRight,
  slideUp,
  slideDown,
  zoomIn,
  zoomOut,
  rotate,
  scaleFade,
  slideScale,
}

/// Helper class to manage random transition selection
class TransitionSelector {
  static final Random _random = Random();
  static final List<SlideTransitionType> _transitions = [
    SlideTransitionType.fade,
    SlideTransitionType.slideLeft,
    SlideTransitionType.slideRight,
    SlideTransitionType.slideUp,
    SlideTransitionType.slideDown,
    SlideTransitionType.zoomIn,
    SlideTransitionType.zoomOut,
    SlideTransitionType.scaleFade,
    SlideTransitionType.slideScale,
  ];

  /// Gets a random transition type
  static SlideTransitionType getRandomTransition() {
    return _transitions[_random.nextInt(_transitions.length)];
  }

  /// Gets transition duration (consistent across all devices)
  static Duration getTransitionDuration(bool isTablet) {
    return const Duration(milliseconds: 500);
  }
}

class ThemeSlideshowScreen extends StatefulWidget {
  const ThemeSlideshowScreen({super.key});

  @override
  State<ThemeSlideshowScreen> createState() => _ThemeSlideshowScreenState();
}

class _ThemeSlideshowScreenState extends State<ThemeSlideshowScreen> {
  late ThemeSlideshowViewModel _viewModel;
  int _currentIndex = 0;
  Timer? _timer;
  SlideTransitionType? _currentTransition;
  bool _isTablet = false;

  @override
  void initState() {
    super.initState();
    _viewModel = ThemeSlideshowViewModel();
    // Capture context before async operation
    final currentContext = context;
    
    // Listen to ViewModel changes to start slideshow when all images are loaded
    _viewModel.addListener(_onViewModelChanged);
    
    _viewModel.fetchThemes().then((_) {
      if (mounted && currentContext.mounted) {
        final imageUrls = _viewModel.getSampleImageUrls();
        if (imageUrls.isNotEmpty) {
          // Start preloading images (first image first, then rest)
          _viewModel.preloadImages(currentContext);
        }
      }
    });
  }

  void _onViewModelChanged() {
    // Only proceed if widget is still mounted
    if (!mounted) return;
    
    // Start slideshow animation when all images are loaded
    if (_viewModel.areAllImagesLoaded && _timer == null) {
      _startSlideshow();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _viewModel.removeListener(_onViewModelChanged);
    _viewModel.dispose();
    super.dispose();
  }

  void _startSlideshow() {
    // Use preloaded image URLs
    final imageUrls = _viewModel.preloadedImageUrls.isNotEmpty
        ? _viewModel.preloadedImageUrls
        : _viewModel.getSampleImageUrls();
    if (imageUrls.isEmpty) return;

    // Set initial random transition
    _currentTransition = TransitionSelector.getRandomTransition();

    // Cancel any existing timer
    _timer?.cancel();

    // Only start animation timer if all images are loaded
    if (!_viewModel.areAllImagesLoaded) {
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // Check if ViewModel is still valid (not disposed)
      try {
        // Check if all images are still loaded
        if (!_viewModel.areAllImagesLoaded) {
          timer.cancel();
          return;
        }

        final imageUrls = _viewModel.preloadedImageUrls.isNotEmpty
            ? _viewModel.preloadedImageUrls
            : _viewModel.getSampleImageUrls();
        if (imageUrls.isEmpty) {
          timer.cancel();
          return;
        }

        final nextIndex = (_currentIndex + 1) % imageUrls.length;
        // Select a new random transition for this change
        if (mounted) {
          setState(() {
            _currentTransition = TransitionSelector.getRandomTransition();
            _currentIndex = nextIndex;
          });
        }
      } catch (e) {
        // ViewModel might be disposed, cancel timer
        debugPrint('Error in slideshow timer: $e');
        timer.cancel();
      }
    });
  }


  Widget _buildTransition(Widget child, Animation<double> animation) {
    final transitionType = _currentTransition ?? SlideTransitionType.fade;
    
    switch (transitionType) {
      case SlideTransitionType.fade:
        return FadeTransition(opacity: animation, child: child);
      
      case SlideTransitionType.slideLeft:
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      
      case SlideTransitionType.slideRight:
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1.0, 0.0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      
      case SlideTransitionType.slideUp:
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 1.0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      
      case SlideTransitionType.slideDown:
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, -1.0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        );
      
      case SlideTransitionType.zoomIn:
        return ScaleTransition(
          scale: Tween<double>(begin: 0.8, end: 1.0).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      
      case SlideTransitionType.zoomOut:
        return ScaleTransition(
          scale: Tween<double>(begin: 1.2, end: 1.0).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      
      case SlideTransitionType.rotate:
        return RotationTransition(
          turns: Tween<double>(begin: 0.0, end: 1.0).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      
      case SlideTransitionType.scaleFade:
        return ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.0).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOut),
          ),
          child: FadeTransition(opacity: animation, child: child),
        );
      
      case SlideTransitionType.slideScale:
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 0.1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOut),
            ),
            child: child,
          ),
        );
    }
  }

  void _onTap() {
    // Use image URLs from themes, prefer preloaded if available
    final imageUrls = _viewModel.preloadedImageUrls.isNotEmpty
        ? _viewModel.preloadedImageUrls
        : _viewModel.getSampleImageUrls();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => TermsAndConditionsScreen(
          carouselImages: imageUrls,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    _isTablet = screenWidth > AppConstants.kTabletBreakpoint;

    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBody: true,
        extendBodyBehindAppBar: true,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: Consumer<ThemeSlideshowViewModel>(
            builder: (context, viewModel, child) {
            if (viewModel.isLoading) {
              return const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              );
            }

            if (viewModel.hasError) {
              return Stack(
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            viewModel.errorMessage ?? 'Failed to load themes',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CupertinoButton(
                              onPressed: () {
                                if (!mounted) return;
                                final currentContext = context;
                                viewModel.fetchThemes().then((_) {
                                  if (mounted && currentContext.mounted) {
                                    viewModel.preloadImages(currentContext).then((_) {
                                      if (mounted) {
                                        _startSlideshow();
                                      }
                                    });
                                  }
                                });
                              },
                              child: const Text('Retry'),
                            ),
                            CupertinoButton(
                              onPressed: () {
                                if (!mounted) return;
                                Navigator.of(context).pushReplacementNamed(
                                  AppConstants.kRouteTerms,
                                );
                              },
                              child: const Text('Continue'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }

            // Get image URLs
            final imageUrls = viewModel.getSampleImageUrls();
            if (imageUrls.isEmpty) {
              return const Center(
                child: Text(
                  'No images available',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              );
            }

            // Show first image immediately if loaded, otherwise show loading
            if (!viewModel.isFirstImageLoaded) {
              return const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              );
            }

            // Use preloaded URLs if available, otherwise use all URLs
            final displayUrls = viewModel.preloadedImageUrls.isNotEmpty
                ? viewModel.preloadedImageUrls
                : imageUrls;

            return GestureDetector(
              onTap: _onTap,
              child: SizedBox.expand(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Slideshow images - fills entire screen
                    Positioned.fill(
                      child: AnimatedSwitcher(
                        // Only animate if all images are loaded, otherwise just show first image
                        duration: viewModel.areAllImagesLoaded
                            ? TransitionSelector.getTransitionDuration(_isTablet)
                            : Duration.zero,
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          // Only show transitions if all images are loaded
                          if (viewModel.areAllImagesLoaded) {
                            return _buildTransition(child, animation);
                          }
                          return child; // No transition, just show the image
                        },
                        child: Container(
                          key: ValueKey<int>(_currentIndex),
                          width: double.infinity,
                          height: double.infinity,
                          decoration: const BoxDecoration(
                            color: Colors.black,
                          ),
                          child: CachedNetworkImage(
                            imageUrl: displayUrls[_currentIndex % displayUrls.length],
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            placeholder: Container(
                              color: Colors.black,
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            errorWidget: Container(
                              color: Colors.black,
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.image_not_supported,
                                      size: 64,
                                      color: Colors.white54,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Image unavailable',
                                      style: TextStyle(
                                        color: Colors.white54,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Theme name on the left side
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: SafeArea(
                        top: false,
                        bottom: true,
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: _isTablet ? 32.0 : 20.0,
                            bottom: _isTablet ? 40.0 : 24.0,
                          ),
                          child: _buildThemeName(viewModel, displayUrls),
                        ),
                      ),
                    ),
                    // Centered overlay button
                    Center(
                      child: IgnorePointer(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: _isTablet ? 48.0 : 32.0,
                            vertical: _isTablet ? 32.0 : 24.0,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(_isTablet ? 16.0 : 12.0),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'ZenAI Photo Booth',
                                style: TextStyle(
                                  fontSize: _isTablet ? 28.0 : 24.0,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              SizedBox(height: _isTablet ? 12.0 : 8.0),
                              Text(
                                'Touch anywhere to start',
                                style: TextStyle(
                                  fontSize: _isTablet ? 18.0 : 16.0,
                                  fontWeight: FontWeight.normal,
                                  color: Colors.white,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildThemeName(ThemeSlideshowViewModel viewModel, List<String> displayUrls) {
    if (displayUrls.isEmpty || viewModel.themes.isEmpty) {
      return const SizedBox.shrink();
    }

    // Get the current image URL
    final currentImageUrl = displayUrls[_currentIndex % displayUrls.length];
    
    // Use ViewModel method to get the theme for this image URL
    final currentTheme = viewModel.getThemeForImageUrl(currentImageUrl);

    if (currentTheme == null) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          currentTheme.name,
          style: TextStyle(
            fontSize: _isTablet ? 32.0 : 28.0,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 0.5,
            shadows: [
              Shadow(
                offset: const Offset(0, 2),
                blurRadius: 4,
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
        if (currentTheme.description.isNotEmpty) ...[
          SizedBox(height: _isTablet ? 8.0 : 4.0),
          Text(
            currentTheme.description,
            style: TextStyle(
              fontSize: _isTablet ? 18.0 : 16.0,
              fontWeight: FontWeight.normal,
              color: Colors.white.withValues(alpha: 0.9),
              letterSpacing: 0.3,
              shadows: [
                Shadow(
                  offset: const Offset(0, 2),
                  blurRadius: 4,
                  color: Colors.black.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

}
