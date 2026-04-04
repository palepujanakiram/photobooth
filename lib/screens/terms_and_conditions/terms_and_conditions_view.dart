import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors, Divider, Orientation, Scaffold;
import 'package:provider/provider.dart';
import 'terms_and_conditions_viewmodel.dart';
import '../../utils/constants.dart';
import '../webview/webview_screen.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/full_screen_loader.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/animated_slideshow_background.dart';

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

  @override
  void initState() {
    super.initState();
    _viewModel = TermsAndConditionsViewModel();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _handleAccept() async {
    final success = await _viewModel.acceptTermsAndCreateSession(null);

    if (success && mounted) {
      Navigator.pushNamed(context, AppConstants.kRouteCapture);
    } else if (mounted && _viewModel.hasError) {
      AppSnackBar.showError(
        context,
        _viewModel.errorMessage ?? 'Failed to accept terms',
      );
    }
  }

  void _openFullTerms() {
    showWebViewUrlSheet(
      context,
      url: AppConstants.kTermsAndConditionsUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    
    // Calculate responsive sizes
    final double horizontalPadding = screenWidth * 0.06;
    final double cardMaxWidth = screenWidth > 600 ? 500.0 : screenWidth * 0.9;
    final double scrollVerticalPadding = isLandscape ? 8.0 : 16.0;

    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Scaffold(
        backgroundColor: appColors.backgroundColor,
        body: SafeArea(
          child: Stack(
            children: [
              // Animated slideshow background (behind consent UI)
              const Positioned.fill(
                child: AnimatedSlideshowBackground(),
              ),
              // Main content (no top logo; card has logo in header)
              Column(
                children: [
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                          vertical: scrollVerticalPadding,
                        ),
                        child: Consumer<TermsAndConditionsViewModel>(
                          builder: (context, viewModel, child) {
                            return ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: cardMaxWidth),
                              child: _buildConsentCard(viewModel, appColors, isLandscape),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              
              // Full screen loader overlay
              Consumer<TermsAndConditionsViewModel>(
                builder: (context, viewModel, child) {
                  if (viewModel.isSubmitting) {
                    return Positioned.fill(
                      child: FullScreenLoader(
                        text: 'Creating Session',
                        loaderColor: Colors.blue,
                        elapsedSeconds: viewModel.elapsedSeconds,
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConsentCard(TermsAndConditionsViewModel viewModel, AppColors appColors, [bool compact = false]) {
    final cardPadding = compact ? 12.0 : 20.0;
    return Container(
      decoration: BoxDecoration(
        color: appColors.cardBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: appColors.shadowColor.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: Zen AI logo left of "Quick Consent"
          Padding(
            padding: EdgeInsets.all(cardPadding),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'lib/images/zen_ai_logo.jpeg',
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Icon(
                      CupertinoIcons.photo,
                      size: 40,
                      color: appColors.textColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Quick Consent',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: appColors.textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          
          // Divider
          Divider(height: 1, color: appColors.dividerColor),
          
          // Content
          Padding(
            padding: EdgeInsets.all(cardPadding),
            child: _buildQuickConsentContent(appColors),
          ),
          
          // Checkbox section
          Container(
            margin: EdgeInsets.symmetric(horizontal: cardPadding),
            padding: EdgeInsets.all(compact ? 12.0 : 16),
            decoration: BoxDecoration(
              color: appColors.backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _buildCheckbox(viewModel, appColors),
          ),
          
          SizedBox(height: compact ? 12 : 20),
          
          // Action button
          Padding(
            padding: EdgeInsets.symmetric(horizontal: cardPadding),
            child: _buildActionButtons(viewModel, appColors),
          ),
          
          SizedBox(height: compact ? 8 : 16),
          
          // View full T&C link
          Center(
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              onPressed: _openFullTerms,
              child: const Text(
                'View Full Terms & Conditions',
                style: TextStyle(
                  fontSize: 14,
                  color: CupertinoColors.systemBlue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildQuickConsentContent(AppColors appColors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'By using this AI Photo Booth, you agree to:',
          style: TextStyle(
            fontSize: 15,
            color: appColors.secondaryTextColor,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        _buildBulletPoint('AI processing of your photo to create transformed images', appColors),
        _buildBulletPoint('Automatic deletion of your data 15 minutes after printing', appColors),
        _buildBulletPoint('All people in the photo have given permission to be photographed', appColors),
        const SizedBox(height: 20),
        Text(
          'Your photos are never sold or shared.',
          style: TextStyle(
            fontSize: 14,
            color: appColors.secondaryTextColor,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildBulletPoint(String text, AppColors appColors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(
              fontSize: 15,
              color: appColors.textColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                color: appColors.textColor,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckbox(TermsAndConditionsViewModel viewModel, AppColors appColors) {
    return GestureDetector(
      onTap: () => viewModel.toggleAgreement(!viewModel.isAgreed),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: viewModel.isAgreed
                    ? CupertinoColors.systemBlue
                    : CupertinoColors.systemGrey,
                width: 2,
              ),
              color: viewModel.isAgreed
                  ? CupertinoColors.systemBlue
                  : Colors.transparent,
            ),
            child: viewModel.isAgreed
                ? const Icon(
                    CupertinoIcons.checkmark,
                    color: CupertinoColors.white,
                    size: 16,
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'I agree to AI photo processing and confirm everyone has consented',
              style: TextStyle(
                fontSize: 14,
                color: appColors.textColor,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(TermsAndConditionsViewModel viewModel, AppColors appColors) {
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 16),
        color: viewModel.canSubmit
            ? CupertinoColors.systemBlue
            : CupertinoColors.systemGrey,
        borderRadius: BorderRadius.circular(12),
        onPressed: viewModel.canSubmit ? _handleAccept : null,
        child: viewModel.isSubmitting
            ? const CupertinoActivityIndicator(
                color: CupertinoColors.white,
              )
            : Text(
                'Start Your Experience',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: viewModel.canSubmit
                      ? CupertinoColors.white
                      : appColors.isDarkMode
                          ? CupertinoColors.white
                          : CupertinoColors.black,
                ),
              ),
      ),
    );
  }
}
