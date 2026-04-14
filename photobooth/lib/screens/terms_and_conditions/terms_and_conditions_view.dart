import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart'
    show Colors, Divider, Orientation, Scaffold, CircularProgressIndicator;
import 'package:provider/provider.dart';
import 'terms_and_conditions_viewmodel.dart';
import '../../utils/constants.dart';
import '../webview/webview_screen.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/full_screen_loader.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/animated_slideshow_background.dart';
import '../../services/session_manager.dart';

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
    final success =
        await _viewModel.acceptTermsAndCreateSession(_viewModel.kioskCode);

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

  Future<void> _showKioskSettings(BuildContext context) async {
    final vm = _viewModel;
    final current = (vm.kioskCode ?? '').trim();

    Future<void> connectOrChange({required String initial}) async {
      final controller = TextEditingController(text: initial);
      final result = await showCupertinoDialog<String?>(
        context: context,
        builder: (ctx) {
          return CupertinoAlertDialog(
            title: Text(current.isEmpty ? 'Connect kiosk' : 'Change kiosk'),
            content: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: CupertinoTextField(
                controller: controller,
                placeholder: 'Enter kiosk code',
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                onChanged: (v) {
                  final up = v.toUpperCase();
                  if (up == v) return;
                  controller.value = controller.value.copyWith(
                    text: up,
                    selection:
                        TextSelection.collapsed(offset: up.length),
                    composing: TextRange.empty,
                  );
                },
              ),
            ),
            actions: [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('Cancel'),
              ),
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
      if (!context.mounted) return;
      if (result == null) return;
      final ok = await vm.validateAndSetKioskCode(result);
      if (!ok) {
        if (!context.mounted) return;
        AppSnackBar.showError(context, vm.errorMessage ?? 'Invalid kiosk code');
        return;
      }
      SessionManager().clearSession();
      if (!context.mounted) return;
      AppSnackBar.showSuccess(context, 'Kiosk updated');
    }

    if (current.isEmpty) {
      await connectOrChange(initial: '');
      return;
    }

    final action = await showCupertinoModalPopup<String?>(
      context: context,
      builder: (ctx) {
        return CupertinoActionSheet(
          title: const Text('Kiosk'),
          message: Text('Connected to: $current'),
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(ctx, 'change'),
              child: const Text('Change kiosk'),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, 'disconnect'),
              child: const Text('Disconnect'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
        );
      },
    );
    if (!context.mounted || action == null) return;
    if (action == 'disconnect') {
      await vm.updateKioskCode(null);
      SessionManager().clearSession();
      if (!context.mounted) return;
      AppSnackBar.showSuccess(context, 'Kiosk disconnected');
      return;
    }
    if (action == 'change') {
      await connectOrChange(initial: current);
    }
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
                              return ConstrainedBox(
                                constraints:
                                    BoxConstraints(maxWidth: cardMaxWidth),
                                child: _buildKioskSetupRequired(
                                  context,
                                  appColors,
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
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  onPressed: () => _showKioskSettings(context),
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

  Widget _buildKioskSetupRequired(
    BuildContext context,
    AppColors appColors,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
      decoration: BoxDecoration(
        color: appColors.cardBackgroundColor.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: appColors.shadowColor.withValues(alpha: 0.12),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Kiosk Setup Required',
            style: TextStyle(
              color: appColors.textColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'This device needs to be provisioned before use. Please enter the kiosk code.',
            style: TextStyle(
              color: appColors.secondaryTextColor,
              fontSize: 13,
              height: 1.35,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: 240,
            child: CupertinoButton(
              color: CupertinoColors.systemBlue,
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.symmetric(vertical: 14),
              onPressed: () => _showKioskSettings(context),
              child: const Text(
                'Link Device to Kiosk',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
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
