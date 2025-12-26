import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../photo_capture/photo_model.dart';
import '../theme_selection/theme_model.dart';
import 'photo_review_viewmodel.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_theme.dart';
import '../../views/widgets/full_screen_loader.dart';
import '../../views/widgets/app_snackbar.dart';

class PhotoReviewScreen extends StatefulWidget {
  const PhotoReviewScreen({super.key});

  @override
  State<PhotoReviewScreen> createState() => _PhotoReviewScreenState();
}

class _PhotoReviewScreenState extends State<PhotoReviewScreen> {
  late ReviewViewModel _reviewViewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null) {
      final photo = args['photo'] as PhotoModel?;
      final theme = args['theme'] as ThemeModel?;
      if (photo != null && theme != null) {
        _reviewViewModel = ReviewViewModel(photo: photo, theme: theme);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args == null) {
      return const Scaffold(
        body: Center(child: Text('Invalid arguments')),
      );
    }

    final photo = args['photo'] as PhotoModel?;
    final theme = args['theme'] as ThemeModel?;

    if (photo == null || theme == null) {
      return const Scaffold(
        body: Center(child: Text('Missing photo or theme')),
      );
    }

    _reviewViewModel = ReviewViewModel(photo: photo, theme: theme);

    return ChangeNotifierProvider.value(
      value: _reviewViewModel,
      child: Stack(
        children: [
          CupertinoPageScaffold(
            navigationBar: const AppTopBar(
              title: 'Review Photo',
            ),
            child: SafeArea(
              child: Consumer<ReviewViewModel>(
                builder: (context, viewModel, child) {
                  return Column(
                    children: [
                      Expanded(
                        child: Center(
                          child: Image.file(
                            viewModel.photo!.imageFile,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            children: [
                              Text(
                                'Theme: ${viewModel.theme?.name ?? "Unknown"}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                viewModel.theme?.description ?? '',
                                style: const TextStyle(fontSize: 14),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              if (viewModel.hasError)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16.0),
                                  child: Text(
                                    viewModel.errorMessage ?? 'Unknown error',
                                    style: const TextStyle(
                                      color: CupertinoColors.systemRed,
                                      fontSize: 14,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              AppContinueButton(
                                text: 'Transform Photo',
                                onPressed: viewModel.isTransforming
                                    ? null
                                    : () async {
                                        // Capture context before async operation
                                        final currentContext = context;

                                        final transformedImage =
                                            await viewModel.transformPhoto();

                                        if (!mounted ||
                                            !currentContext.mounted) {
                                          return;
                                        }

                                        if (transformedImage != null) {
                                          // Navigate to result screen on success
                                          Navigator.pushNamed(
                                            currentContext,
                                            AppConstants.kRouteResult,
                                            arguments: {
                                              'transformedImage':
                                                  transformedImage,
                                            },
                                          );
                                        } else if (viewModel.hasError) {
                                          // Show error with status code if available
                                          final errorMessage =
                                              viewModel.errorMessage ??
                                                  'Unknown error';
                                          AppSnackBar.showError(
                                            currentContext,
                                            errorMessage,
                                          );
                                        }
                                      },
                                isLoading: viewModel.isTransforming,
                                padding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          // Full screen loader overlay
          Consumer<ReviewViewModel>(
            builder: (context, viewModel, child) {
              if (viewModel.isTransforming) {
                return const FullScreenLoader(
                  text: 'Generating AI Image',
                  loaderColor: CupertinoColors.systemBlue,
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }
}
