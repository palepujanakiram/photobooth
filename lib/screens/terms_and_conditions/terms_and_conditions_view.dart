import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'terms_and_conditions_viewmodel.dart';
import '../../utils/constants.dart';
import '../../utils/app_config.dart';
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
  int _currentPage = 0;
  Timer? _carouselTimer;

  @override
  void initState() {
    super.initState();
    _viewModel = TermsAndConditionsViewModel();
    _kioskNameController.addListener(() {
      _viewModel.updateKioskName(_kioskNameController.text);
    });
    // Start auto-scrolling carousel after a short delay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startCarouselAutoScroll();
    });
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _kioskNameController.dispose();
    _pageController.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  void _startCarouselAutoScroll() {
    final carouselImages = widget.carouselImages ?? [];
    if (carouselImages.isEmpty) return;

    _carouselTimer?.cancel();
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final nextPage = (_currentPage + 1) % carouselImages.length;
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
      MaterialPageRoute(
        builder: (context) => const WebViewScreen(
          url: AppConfig.termsAndConditionsUrl,
          title: 'Terms and Conditions',
        ),
      ),
    );
  }

  Future<void> _handleAccept() async {
    final kioskName = _kioskNameController.text.trim();
    if (kioskName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('KIOSK name cannot be empty'),
        ),
      );
      return;
    }

    final success = await _viewModel.acceptTerms(kioskName);
    if (success && mounted) {
      Navigator.pushReplacementNamed(context, AppConstants.kRouteHome);
    } else if (mounted && _viewModel.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_viewModel.errorMessage ?? 'Failed to accept terms'),
          backgroundColor: Colors.red,
        ),
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
    final double privacyNoteSpacing = isTablet ? 8.0 : 4.0;
    
    // Adjust carousel height based on available space - increased size
    final double carouselHeight = isTablet 
        ? (availableHeight * 0.30).clamp(250.0, 350.0)
        : (availableHeight * 0.28).clamp(180.0, 250.0);
    
    // Adjust logo size - tripled for better visibility
    final double logoSize = isTablet ? 240.0 : 180.0;
    final double logoIconSize = isTablet ? 40.0 : 30.0;

    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Padding(
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
                            color: Colors.grey[700],
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
                        SizedBox(height: privacyNoteSpacing),
                      ],
                    );
                  },
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
                color: Colors.blue[900],
              ),
            ),
            Text(
              'PHOTO BOOTH',
              style: TextStyle(
                fontSize: logoSize * 0.15,
                color: Colors.grey[600],
                letterSpacing: 2,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildImageCarousel(bool isTablet, double height) {
    // Use theme images if provided, otherwise use default images
    final List<String> carouselImages = widget.carouselImages ?? [
      'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?w=800&h=600&fit=crop',
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=800&h=600&fit=crop',
      'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=800&h=600&fit=crop',
      'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=800&h=600&fit=crop',
    ];
    
    if (carouselImages.isEmpty) {
      return const SizedBox.shrink();
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
              // Reset timer when page changes manually
              _startCarouselAutoScroll();
            },
            itemCount: carouselImages.length,
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
                    child: Image.network(
                      carouselImages[index],
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: Colors.transparent,
                        child: Center(
                          child: CircularProgressIndicator(
                            value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                            color: Colors.blue,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: Colors.transparent,
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.image_not_supported,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Image unavailable',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
          children: List.generate(carouselImages.length, (index) {
            return Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentPage == index
                    ? Colors.blue
                    : Colors.grey[300],
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
          icon: Icons.camera_alt,
          label: 'Take Photo',
          isTablet: isTablet,
        ),
        _buildActionButton(
          icon: Icons.auto_awesome,
          label: 'AI Transform',
          isTablet: isTablet,
        ),
        _buildActionButton(
          icon: Icons.print,
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
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: isTablet ? 28 : 24,
              color: Colors.blue[700],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: isTablet ? 12 : 10,
                color: Colors.blue[700],
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
    return TextField(
      controller: _kioskNameController,
      decoration: InputDecoration(
        labelText: 'KIOSK Name',
        hintText: 'Enter KIOSK name',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: isTablet ? 14 : 10,
        ),
        isDense: true,
      ),
      textCapitalization: TextCapitalization.words,
      style: TextStyle(fontSize: isTablet ? 16 : 14),
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
                  : Colors.transparent,
            ),
            child: viewModel.isAgreed
                ? const Icon(
                    Icons.check,
                    color: Colors.white,
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
                  color: Colors.grey[700],
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
                      color: Colors.blue[700],
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
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[400],
          foregroundColor: Colors.white,
          textStyle: TextStyle(
            fontSize: isTablet ? 18.0 : 16.0,
            fontWeight: FontWeight.bold,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        onPressed: viewModel.canSubmit ? _handleAccept : null,
        child: viewModel.isSubmitting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Text('Start Your Experience'),
      ),
    );
  }

  Widget _buildPrivacyNote(bool isTablet) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.access_time,
          size: isTablet ? 14 : 12,
          color: Colors.grey[600],
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            'Sessions auto-delete after 24 hours for your privacy',
            style: TextStyle(
              fontSize: isTablet ? 11 : 10,
              color: Colors.grey[600],
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
