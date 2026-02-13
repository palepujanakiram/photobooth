import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:provider/provider.dart';
import 'theme_selection_viewmodel.dart';
import '../photo_capture/photo_model.dart';
import '../../utils/constants.dart';
import '../../views/widgets/theme_card.dart';
import '../../views/widgets/app_theme.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/full_screen_loader.dart';
import '../../services/theme_manager.dart';

class ThemeSelectionScreen extends StatefulWidget {
  const ThemeSelectionScreen({super.key});

  @override
  State<ThemeSelectionScreen> createState() => _ThemeSelectionScreenState();
}

class _ThemeSelectionScreenState extends State<ThemeSelectionScreen> {
  PhotoModel? _photoFromCapture;
  bool _isGenerating = false;
  Timer? _timer;
  int _elapsedSeconds = 0;

  void _startTimer() {
    _elapsedSeconds = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedSeconds++;
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final viewModel = context.read<ThemeViewModel>();
      // Use cached themes immediately if available (faster)
      final themeManager = ThemeManager();
      if (themeManager.hasThemes) {
        // Update themes from cache immediately
        viewModel.updateFromCache();
      }
      // Then fetch/refresh themes
      viewModel.loadThemes();

      // Check if we have a photo from capture screen
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args != null && args is Map) {
        _photoFromCapture = args['photo'] as PhotoModel?;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > AppConstants.kTabletBreakpoint;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop) {
          Navigator.pushNamed(
            context,
            AppConstants.kRouteTerms,
          );
        }
      },
      child: Stack(
        children: [
          CupertinoPageScaffold(
            navigationBar: AppTopBar(
              title: 'Select Theme',
              leading: AppActionButton(
                icon: CupertinoIcons.back,
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    AppConstants.kRouteTerms,
                  );
                },
              ),
            ),
            child: SafeArea(
              child: Consumer<ThemeViewModel>(
                builder: (context, viewModel, child) {
                  if (viewModel.isLoading) {
                    return const Center(
                      child: CupertinoActivityIndicator(),
                    );
                  }

                  if (viewModel.hasError) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            CupertinoIcons.exclamationmark_triangle,
                            size: 64,
                            color: CupertinoColors.systemRed,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            viewModel.errorMessage ?? 'Unknown error',
                            style: const TextStyle(fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          CupertinoButton(
                            onPressed: () => viewModel.loadThemes(),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }

                  if (viewModel.themes.isEmpty) {
                    return const Center(
                      child: Text('No themes available'),
                    );
                  }

                  return Column(
                    children: [
                      // Step banner at the top
                      _buildStepBanner(context, 1), // 1 = Select Theme step
                      
                      Expanded(
                        child: GridView.builder(
                          padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isTablet ? 3 : 2,
                            crossAxisSpacing: 16.0,
                            mainAxisSpacing: 16.0,
                            childAspectRatio: isTablet ? 0.75 : 0.7,
                          ),
                          itemCount: viewModel.themes.length,
                          itemBuilder: (context, index) {
                            final theme = viewModel.themes[index];
                            final isSelected = viewModel.selectedTheme?.id == theme.id;

                            return ThemeCard(
                              theme: theme,
                              isSelected: isSelected,
                              onTap: () {
                                viewModel.selectTheme(theme);
                              },
                            );
                          },
                        ),
                      ),
                      // Continue button at bottom
                      Padding(
                        padding: EdgeInsets.only(
                          left: isTablet ? 24.0 : 16.0,
                          right: isTablet ? 24.0 : 16.0,
                          bottom: isTablet ? 24.0 : 16.0,
                        ),
                        child: AppContinueButton(
                          onPressed: viewModel.selectedTheme != null &&
                                  !_isGenerating &&
                                  !viewModel.isUpdatingSession
                              ? () async {
                                  final selectedTheme = viewModel.selectedTheme;
                                  if (selectedTheme == null) return;

                                  // Capture context before async operation
                                  final currentContext = context;

                                  // If we have a photo from capture, update session with theme
                                  if (_photoFromCapture != null) {
                                    // Show full screen loader
                                    _startTimer();
                                    setState(() {
                                      _isGenerating = true;
                                    });

                                    bool success = false;
                                    try {
                                      // Step 4: Update session with selected theme
                                      // PATCH /api/sessions/{sessionId} with only selectedThemeId
                                      success = await viewModel.updateSessionWithTheme();

                                      if (!mounted || !currentContext.mounted) return;

                                      if (success) {
                                        // Navigate to Generate Photo screen
                                        Navigator.pushNamed(
                                          currentContext,
                                          AppConstants.kRouteGenerate,
                                          arguments: {
                                            'photo': _photoFromCapture,
                                            'theme': selectedTheme,
                                          },
                                        );
                                      } else {
                                        // Show animated error if update fails
                                        AppSnackBar.showError(
                                          currentContext,
                                          viewModel.errorMessage ??
                                              'Failed to update session with theme',
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted && currentContext.mounted) {
                                        AppSnackBar.showError(
                                          currentContext,
                                          'An error occurred: ${e.toString()}',
                                        );
                                      }
                                    } finally {
                                      // Always clear loader and timer so UI cannot hang
                                      _stopTimer();
                                      if (mounted) {
                                        setState(() {
                                          _isGenerating = false;
                                        });
                                      }
                                    }
                                  } else {
                                    // Normal flow: navigate to capture photo
                                    Navigator.pushNamed(
                                      currentContext,
                                      AppConstants.kRouteCapture,
                                    );
                                  }
                                }
                              : null,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          // Full screen loader overlay - positioned to cover entire screen
          if (_isGenerating)
            Positioned.fill(
              child: FullScreenLoader(
                text: 'Updating Session',
                loaderColor: CupertinoColors.systemBlue,
                elapsedSeconds: _elapsedSeconds,
              ),
            ),
        ],
      ),
    );
  }

  /// Builds the step progress banner
  Widget _buildStepBanner(BuildContext context, int currentStep) {
    final appColors = AppColors.of(context);
    
    final steps = [
      _StepInfo(icon: CupertinoIcons.camera, label: 'Photo'),
      _StepInfo(icon: CupertinoIcons.paintbrush, label: 'Select Theme'),
      _StepInfo(icon: CupertinoIcons.sparkles, label: 'Generate'),
      _StepInfo(icon: CupertinoIcons.tray_arrow_down, label: 'Pay & Collect'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: appColors.backgroundColor,
        boxShadow: [
          BoxShadow(
            color: appColors.shadowColor.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(steps.length, (index) {
          final step = steps[index];
          final isActive = index == currentStep;
          final isCompleted = index < currentStep;
          
          return Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isActive 
                              ? CupertinoColors.systemBlue.withValues(alpha: 0.1)
                              : isCompleted
                                  ? CupertinoColors.systemBlue
                                  : Colors.transparent,
                          border: Border.all(
                            color: isActive || isCompleted
                                ? CupertinoColors.systemBlue
                                : CupertinoColors.systemGrey3,
                            width: isActive ? 2 : 1,
                          ),
                        ),
                        child: Icon(
                          isCompleted ? CupertinoIcons.checkmark : step.icon,
                          size: 18,
                          color: isCompleted
                              ? CupertinoColors.white
                              : isActive
                                  ? CupertinoColors.systemBlue
                                  : CupertinoColors.systemGrey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        step.label,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                          color: isActive || isCompleted
                              ? CupertinoColors.systemBlue
                              : CupertinoColors.systemGrey,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Connector line (except for last item)
                if (index < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 1,
                      margin: const EdgeInsets.only(bottom: 20),
                      color: isCompleted
                          ? CupertinoColors.systemBlue
                          : CupertinoColors.systemGrey3,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

/// Helper class to store step information
class _StepInfo {
  final IconData icon;
  final String label;

  _StepInfo({required this.icon, required this.label});
}
