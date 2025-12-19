import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'terms_and_conditions_viewmodel.dart';
import '../../utils/constants.dart';
import '../../utils/app_config.dart';
import 'webview_screen.dart';

class TermsAndConditionsScreen extends StatefulWidget {
  const TermsAndConditionsScreen({super.key});

  @override
  State<TermsAndConditionsScreen> createState() =>
      _TermsAndConditionsScreenState();
}

class _TermsAndConditionsScreenState extends State<TermsAndConditionsScreen> {
  late TermsAndConditionsViewModel _viewModel;
  final TextEditingController _kioskNameController = TextEditingController();
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _viewModel = TermsAndConditionsViewModel();
    _kioskNameController.addListener(() {
      _viewModel.updateKioskName(_kioskNameController.text);
    });
  }

  @override
  void dispose() {
    _kioskNameController.dispose();
    _pageController.dispose();
    _viewModel.dispose();
    super.dispose();
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
    final isTablet = screenWidth > AppConstants.kTabletBreakpoint;

    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 32.0 : 20.0,
                vertical: isTablet ? 32.0 : 20.0,
              ),
              child: Consumer<TermsAndConditionsViewModel>(
                builder: (context, viewModel, child) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),
                      // Logo Section
                      _buildLogo(),
                      const SizedBox(height: 32),
                      // Image Carousel
                      _buildImageCarousel(isTablet),
                      const SizedBox(height: 24),
                      // Tagline
                      Text(
                        'Snap. Transform. Take Home Magic.',
                        style: TextStyle(
                          fontSize: isTablet ? 20.0 : 16.0,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      // Action Buttons
                      _buildActionButtons(isTablet),
                      const SizedBox(height: 40),
                      // KIOSK Name Field
                      _buildKioskNameField(isTablet),
                      const SizedBox(height: 24),
                      // Checkbox
                      _buildCheckbox(viewModel),
                      const SizedBox(height: 24),
                      // Start Your Experience Button
                      _buildStartButton(viewModel, isTablet),
                      const SizedBox(height: 16),
                      // Privacy Note
                      _buildPrivacyNote(),
                      const SizedBox(height: 20),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF9B59B6), Color(0xFFE74C3C), Color(0xFFF39C12)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.camera_alt,
            color: Colors.white,
            size: 40,
          ),
        ),
        const SizedBox(height: 12),
        Column(
          children: [
            Text(
              'Zen AI',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.blue[900],
              ),
            ),
            Text(
              'PHOTO BOOTH',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildImageCarousel(bool isTablet) {
    // Sample photo booth transformation images
    final List<String> carouselImages = [
      'https://images.unsplash.com/photo-1515886657613-9f3515b0c78f?w=800&h=600&fit=crop',
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=800&h=600&fit=crop',
      'https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=800&h=600&fit=crop',
      'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?w=800&h=600&fit=crop',
    ];

    return Column(
      children: [
        SizedBox(
          height: isTablet ? 300 : 250,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
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
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        color: Colors.grey[200],
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
                        color: Colors.grey[200],
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
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(carouselImages.length, (index) {
            return Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 4),
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
        padding: EdgeInsets.all(isTablet ? 16.0 : 12.0),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: isTablet ? 32 : 28,
              color: Colors.blue[700],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: isTablet ? 14 : 12,
                color: Colors.blue[700],
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
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
          vertical: isTablet ? 16 : 12,
        ),
      ),
      textCapitalization: TextCapitalization.words,
      style: TextStyle(fontSize: isTablet ? 16 : 14),
    );
  }

  Widget _buildCheckbox(TermsAndConditionsViewModel viewModel) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: viewModel.isAgreed,
          onChanged: (value) {
            viewModel.toggleAgreement(value ?? false);
          },
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: GestureDetector(
              onTap: () {
                viewModel.toggleAgreement(!viewModel.isAgreed);
              },
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(
                      text: 'I have read and agree to the ',
                    ),
                    TextSpan(
                      text: 'Terms & Conditions',
                      style: TextStyle(
                        fontSize: 14,
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
        ),
      ],
    );
  }

  Widget _buildStartButton(
      TermsAndConditionsViewModel viewModel, bool isTablet) {
    return SizedBox(
      width: double.infinity,
      height: isTablet ? 60.0 : 56.0,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue[400],
          foregroundColor: Colors.white,
          textStyle: TextStyle(
            fontSize: isTablet ? 20.0 : 18.0,
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

  Widget _buildPrivacyNote() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.access_time,
          size: 16,
          color: Colors.grey[600],
        ),
        const SizedBox(width: 6),
        Text(
          'Sessions auto-delete after 24 hours for your privacy',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
