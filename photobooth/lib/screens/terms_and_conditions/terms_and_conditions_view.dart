import 'dart:async' show unawaited;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Colors, Divider, Orientation, Scaffold, CircularProgressIndicator;
import 'package:provider/provider.dart';
import 'terms_and_conditions_viewmodel.dart';
import 'terms_layout_metrics.dart';
import '../../utils/constants.dart';
import '../../utils/camera_permission_helper.dart';
import '../splash/bootstrap_route_args.dart';
import '../webview/webview_screen.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/full_screen_loader.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/animated_slideshow_background.dart';
import '../../views/widgets/centered_max_width.dart';

class TermsAndConditionsScreen extends StatefulWidget {
  /// Theme sample image URLs for the animated background; null uses default assets.
  final List<String>? backgroundImageUrls;

  const TermsAndConditionsScreen({
    super.key,
    this.backgroundImageUrls,
  });

  @override
  State<TermsAndConditionsScreen> createState() =>
      _TermsAndConditionsScreenState();
}

class _TermsAndConditionsScreenState extends State<TermsAndConditionsScreen> {
  late TermsAndConditionsViewModel _viewModel;
  bool _redirectingToSplash = false;
  Object? _capturePrefillPhoto;

  @override
  void initState() {
    super.initState();
    _viewModel = TermsAndConditionsViewModel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(primeCameraPermissionOnTermsLaunch());
    });
  }

  void _redirectToSplashForKioskSetup() {
    if (_redirectingToSplash || !mounted) return;
    _redirectingToSplash = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(AppConstants.kRouteSplash);
    });
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _handleAccept() async {
    final success =
        await _viewModel.acceptTermsAndCreateSession(_viewModel.kioskCode);

    if (success && mounted) {
      Navigator.pushReplacementNamed(
        context,
        AppConstants.kRouteCapture,
        arguments: _capturePrefillPhoto == null
            ? null
            : <String, Object?>{'photo': _capturePrefillPhoto},
      );
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

  Future<void> _openKioskManagement(BuildContext context) async {
    await Navigator.of(context).pushNamed(
      AppConstants.kRouteSplash,
      arguments: const SplashRouteArgs(manageKiosk: true),
    );
    if (!mounted) return;
    await _viewModel.reloadKioskFromStorage();
  }

  @override
  Widget build(BuildContext context) {
    final rawArgs = ModalRoute.of(context)?.settings.arguments;
    if (_capturePrefillPhoto == null && rawArgs is TermsRouteArgs) {
      _capturePrefillPhoto = rawArgs.capturePhoto;
    }
    final appColors = AppColors.of(context);
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    
    final layout = TermsLayoutMetrics(
      screenWidth: screenWidth,
      isLandscape: isLandscape,
    );
    final double horizontalPadding = screenWidth * 0.06;
    final double cardMaxWidth = layout.cardMaxWidth;
    final double scrollVerticalPadding = layout.scrollVerticalPadding;

    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Scaffold(
        backgroundColor: appColors.backgroundColor,
        body: SafeArea(
          child: Stack(
            children: [
              // Animated slideshow (theme samples when provided, else default assets)
              Positioned.fill(
                child: AnimatedSlideshowBackground(
                  assetPaths: widget.backgroundImageUrls,
                ),
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
                            // Gate the whole flow until the kiosk is provisioned.
                            final kioskCode = (viewModel.kioskCode ?? '').trim();
                            if (!viewModel.kioskCodeLoaded) {
                              return ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: cardMaxWidth),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: appColors.primaryColor,
                                  ),
                                ),
                              );
                            }
                            if (kioskCode.isEmpty) {
                              _redirectToSplashForKioskSetup();
                              return ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: cardMaxWidth),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: appColors.primaryColor,
                                  ),
                                ),
                              );
                            }
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
    final layout = TermsLayoutMetrics(
      screenWidth: MediaQuery.sizeOf(context).width,
      isLandscape: compact,
    );
    final cardPadding = layout.cardPadding(compact: compact);
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
          // Header: Fotozen AI logo left of "Quick Consent"
          Padding(
            padding: EdgeInsets.all(cardPadding),
            child: Row(
              children: [
                SizedBox(
                  width: 132,
                  height: 40,
                  child: Image.asset(
                    AppConstants.kBrandLogoAsset,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
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
                    'Terms',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: appColors.textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => _openKioskManagement(context),
                  child: Icon(
                    CupertinoIcons.gear_alt_fill,
                    color: appColors.textColor.withValues(alpha: 0.9),
                    size: 22,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildQuickConsentContent(appColors),
              ],
            ),
          ),
          
          // Checkbox section
          Container(
            margin: EdgeInsets.symmetric(horizontal: cardPadding),
            padding: EdgeInsets.all(layout.checkboxAreaPadding(compact: compact)),
            decoration: BoxDecoration(
              color: appColors.backgroundColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _buildCheckbox(viewModel, appColors),
          ),
          
          SizedBox(height: layout.sectionGap(compact: compact)),

          if (viewModel.hasError) ...[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: cardPadding),
              child: Text(
                viewModel.errorMessage!,
                style: const TextStyle(
                  color: CupertinoColors.systemRed,
                  fontSize: 14,
                  height: 1.35,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: layout.innerSectionGap(compact: compact)),
          ],
          
          // Action button
          Padding(
            padding: EdgeInsets.symmetric(horizontal: cardPadding),
            child: _buildActionButtons(viewModel, appColors),
          ),
          
          SizedBox(height: layout.innerSectionGap(compact: compact)),
          
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
          'Review and accept to get started.',
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

  Color _checkboxBorderColor(bool agreed) {
    if (agreed) return CupertinoColors.systemBlue;
    return CupertinoColors.systemGrey;
  }

  Color _checkboxFillColor(bool agreed) {
    if (agreed) return CupertinoColors.systemBlue;
    return Colors.transparent;
  }

  Color _startButtonLabelColor(bool canSubmit, AppColors appColors) {
    if (canSubmit) return CupertinoColors.white;
    if (appColors.isDarkMode) return CupertinoColors.white;
    return CupertinoColors.black;
  }

  Widget _buildCheckbox(TermsAndConditionsViewModel viewModel, AppColors appColors) {
    final agreed = viewModel.isAgreed;
    return GestureDetector(
      onTap: () => viewModel.toggleAgreement(!agreed),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: _checkboxBorderColor(agreed),
                width: 2,
              ),
              color: _checkboxFillColor(agreed),
            ),
            child: agreed
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
    return CenteredMaxWidth(
      maxWidth: 360,
      child: SizedBox(
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
                    color: _startButtonLabelColor(
                      viewModel.canSubmit,
                      appColors,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
