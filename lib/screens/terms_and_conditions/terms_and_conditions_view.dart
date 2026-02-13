import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'terms_and_conditions_viewmodel.dart';
import '../../utils/constants.dart';
import '../../utils/app_config.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/full_screen_loader.dart';
import '../../views/widgets/app_colors.dart';

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
    showCupertinoModalPopup(
      context: context,
      builder: (context) => const _TermsWebViewSheet(
        url: AppConfig.termsAndConditionsUrl,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    
    // Calculate responsive sizes
    final double horizontalPadding = screenWidth * 0.06;
    final double cardMaxWidth = screenWidth > 600 ? 500.0 : screenWidth * 0.9;

    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: CupertinoPageScaffold(
        backgroundColor: appColors.backgroundColor,
        child: SafeArea(
          child: Stack(
            children: [
              // Main content
              Column(
                children: [
                  // Logo at top
                  Padding(
                    padding: const EdgeInsets.only(top: 24, bottom: 16),
                    child: _buildLogo(appColors),
                  ),
                  
                  // Scrollable content area
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.symmetric(
                          horizontal: horizontalPadding,
                          vertical: 16,
                        ),
                        child: Consumer<TermsAndConditionsViewModel>(
                          builder: (context, viewModel, child) {
                            return ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: cardMaxWidth),
                              child: _buildConsentCard(viewModel, appColors),
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
                        loaderColor: CupertinoColors.systemBlue,
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

  Widget _buildLogo(AppColors appColors) {
    return Image.asset(
      'lib/images/zen_ai_logo.jpeg',
      height: 80,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Text(
          'FotoZen.AI',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: appColors.textColor,
          ),
        );
      },
    );
  }

  Widget _buildConsentCard(TermsAndConditionsViewModel viewModel, AppColors appColors) {
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
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    CupertinoIcons.shield_fill,
                    color: CupertinoColors.systemBlue,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Quick Consent',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: appColors.textColor,
                  ),
                ),
              ],
            ),
          ),
          
          // Divider
          Divider(height: 1, color: appColors.dividerColor),
          
          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: _buildQuickConsentContent(appColors),
          ),
          
          // Checkbox section
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: appColors.backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _buildCheckbox(viewModel, appColors),
          ),
          
          const SizedBox(height: 20),
          
          // Action button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _buildActionButtons(viewModel, appColors),
          ),
          
          const SizedBox(height: 16),
          
          // View full T&C link
          Center(
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              onPressed: _openFullTerms,
              child: const Text(
                'View full Terms & Conditions',
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

/// Modal sheet that displays the full Terms & Conditions in a WebView
class _TermsWebViewSheet extends StatefulWidget {
  final String url;

  const _TermsWebViewSheet({required this.url});

  @override
  State<_TermsWebViewSheet> createState() => _TermsWebViewSheetState();
}

class _TermsWebViewSheetState extends State<_TermsWebViewSheet> {
  WebViewController? _controller;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    try {
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (String url) {
              if (mounted) {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
              }
            },
            onPageFinished: (String url) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
            },
            onWebResourceError: (WebResourceError error) {
              if (mounted) {
                setState(() {
                  _isLoading = false;
                  _errorMessage = 'Failed to load page: ${error.description}';
                });
              }
            },
          ),
        );

      setState(() {
        _controller = controller;
      });

      // Load URL after a small delay to ensure platform is ready
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _controller != null) {
          _controller!.loadRequest(Uri.parse(widget.url));
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to initialize WebView: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    
    return Container(
      height: screenHeight * 0.9,
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
          
          // Header with close button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Terms & Conditions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: appColors.textColor,
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.all(8),
                  onPressed: () => Navigator.pop(context),
                  child: const Icon(
                    CupertinoIcons.xmark_circle_fill,
                    color: CupertinoColors.systemGrey,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
          
          // Divider
          Divider(height: 1, color: appColors.dividerColor),
          
          // WebView content
          Expanded(
            child: _buildWebViewContent(appColors),
          ),
        ],
      ),
    );
  }

  Widget _buildWebViewContent(AppColors appColors) {
    if (_controller == null) {
      return const Center(
        child: CupertinoActivityIndicator(),
      );
    }

    if (_errorMessage != null && !_isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_triangle,
                size: 48,
                color: CupertinoColors.systemRed,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: TextStyle(
                  fontSize: 14,
                  color: appColors.textColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              CupertinoButton(
                color: CupertinoColors.systemBlue,
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                    _isLoading = true;
                  });
                  _controller?.reload();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        WebViewWidget(controller: _controller!),
        if (_isLoading)
          const Center(
            child: CupertinoActivityIndicator(),
          ),
      ],
    );
  }
}
