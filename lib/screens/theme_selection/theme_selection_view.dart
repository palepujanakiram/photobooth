import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'theme_selection_viewmodel.dart';
import '../photo_capture/photo_model.dart';
import '../photo_capture/photo_capture_viewmodel.dart';
import '../../utils/constants.dart';
import '../../views/widgets/theme_card.dart';
import '../../views/widgets/app_theme.dart';
import '../../views/widgets/app_snackbar.dart';
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
            navigationBar: const AppTopBar(
              title: 'Select Theme',
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
                      Expanded(
                        child: GridView.builder(
                          padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isTablet ? 3 : 2,
                            crossAxisSpacing: 16.0,
                            mainAxisSpacing: 16.0,
                            childAspectRatio: isTablet ? 0.75 : 0.7,
                          ),
                          itemCount: viewModel.themes.length,
                          itemBuilder: (context, index) {
                            final theme = viewModel.themes[index];
                            final isSelected =
                                viewModel.selectedTheme?.id == theme.id;

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
                                  !_isGenerating
                              ? () async {
                                  final selectedTheme = viewModel.selectedTheme;
                                  if (selectedTheme == null) return;

                                  // Capture context before async operation
                                  final currentContext = context;

                                  // If we have a photo from capture, show loader and update session
                                  if (_photoFromCapture != null) {
                                    // Show full screen loader
                                    setState(() {
                                      _isGenerating = true;
                                    });

                                    try {
                                      // Update session with photo and theme
                                      final captureViewModel =
                                          CaptureViewModel();
                                      // Set the captured photo in the view model
                                      captureViewModel.capturedPhoto =
                                          _photoFromCapture;

                                      final success = await captureViewModel
                                          .updateSessionWithPhoto(
                                        selectedTheme.id,
                                      );

                                      if (!mounted || !currentContext.mounted) {
                                        setState(() {
                                          _isGenerating = false;
                                        });
                                        return;
                                      }

                                      setState(() {
                                        _isGenerating = false;
                                      });

                                      if (success) {
                                        Navigator.pushNamed(
                                          currentContext,
                                          AppConstants.kRouteReview,
                                          arguments: {
                                            'photo': _photoFromCapture,
                                            'theme': selectedTheme,
                                          },
                                        );
                                      } else {
                                        // Show animated error if update fails
                                        AppSnackBar.showError(
                                          currentContext,
                                          captureViewModel.errorMessage ??
                                              'Failed to update session',
                                        );
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        setState(() {
                                          _isGenerating = false;
                                        });
                                        AppSnackBar.showError(
                                          currentContext,
                                          'An error occurred: ${e.toString()}',
                                        );
                                      }
                                    }
                                  } else {
                                    // Normal flow: navigate to camera selection
                                    Navigator.pushNamed(
                                      currentContext,
                                      AppConstants.kRouteCameraSelection,
                                    );
                                  }
                                }
                              : null,
                          padding: EdgeInsets
                              .zero, // AppContinueButton has its own padding
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
            const Positioned.fill(
              child: FullScreenLoader(
                text: 'Creating Session',
                loaderColor: CupertinoColors.systemBlue,
              ),
            ),
        ],
      ),
    );
  }
}
