import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../photo_capture/photo_model.dart';
import '../theme_selection/theme_model.dart';
import 'photo_review_viewmodel.dart';
import '../../utils/constants.dart';
import '../../utils/app_config.dart';
import '../../views/widgets/app_theme.dart';
import '../../views/widgets/full_screen_loader.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/cached_network_image.dart';

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
            backgroundColor: CupertinoColors.systemBackground,
            navigationBar: const AppTopBar(
              title: 'Review Photo',
            ),
            child: SafeArea(
              top: true,
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final bottomPadding = MediaQuery.of(context).padding.bottom;
                  return Consumer<ReviewViewModel>(
                    builder: (context, viewModel, child) {
                      return Container(
                        width: double.infinity,
                        height: constraints.maxHeight,
                        color: CupertinoColors.systemBackground,
                        padding:
                            const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 0.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.max,
                          children: [
                            // Side by side layout for Captured Photo and Selected Theme
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Left side: Captured Photo
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Captured Photo',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Expanded(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color:
                                                  CupertinoColors.systemGrey6,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: FutureBuilder<List<int>>(
                                                future: viewModel
                                                    .photo!.imageFile
                                                    .readAsBytes(),
                                                builder: (context, snapshot) {
                                                  if (snapshot
                                                          .connectionState ==
                                                      ConnectionState.waiting) {
                                                    return const Center(
                                                      child:
                                                          CupertinoActivityIndicator(),
                                                    );
                                                  }
                                                  if (snapshot.hasError ||
                                                      !snapshot.hasData) {
                                                    return const Center(
                                                      child: Icon(
                                                        CupertinoIcons
                                                            .exclamationmark_triangle,
                                                        color: CupertinoColors
                                                            .systemRed,
                                                        size: 48,
                                                      ),
                                                    );
                                                  }
                                                  return Image.memory(
                                                    Uint8List.fromList(
                                                        snapshot.data!),
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  // Right side: Selected Theme
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Selected Theme',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Expanded(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color:
                                                  CupertinoColors.systemGrey6,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              child: viewModel.theme
                                                              ?.sampleImageUrl !=
                                                          null &&
                                                      viewModel
                                                          .theme!
                                                          .sampleImageUrl!
                                                          .isNotEmpty
                                                  ? _buildThemeImage(
                                                      viewModel.theme!
                                                          .sampleImageUrl!,
                                                    )
                                                  : Container(
                                                      color: CupertinoColors
                                                          .systemGrey5,
                                                      child: Column(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          const Icon(
                                                            CupertinoIcons
                                                                .paintbrush,
                                                            size: 64,
                                                            color:
                                                                CupertinoColors
                                                                    .systemGrey,
                                                          ),
                                                          const SizedBox(
                                                              height: 16),
                                                          Text(
                                                            viewModel.theme
                                                                    ?.name ??
                                                                'Unknown',
                                                            style:
                                                                const TextStyle(
                                                              fontSize: 18,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                          const SizedBox(
                                                              height: 8),
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        16.0),
                                                            child: Text(
                                                              viewModel.theme
                                                                      ?.description ??
                                                                  '',
                                                              style:
                                                                  const TextStyle(
                                                                      fontSize:
                                                                          14),
                                                              textAlign:
                                                                  TextAlign
                                                                      .center,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Error message and button section
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
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: 16.0 + bottomPadding,
                              ),
                              child: AppContinueButton(
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
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          // Full screen loader overlay - positioned to cover entire screen
          Consumer<ReviewViewModel>(
            builder: (context, viewModel, child) {
              if (viewModel.isTransforming) {
                return const Positioned.fill(
                  child: FullScreenLoader(
                    text: 'Generating AI Image',
                    loaderColor: CupertinoColors.systemBlue,
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
    );
  }

  /// Builds theme image with proper URL handling
  /// Fills available space like the captured photo
  Widget _buildThemeImage(String imageUrl) {
    // Handle URL construction like ThemeCard does
    String fullUrl = imageUrl;
    if (!imageUrl.startsWith('http://') && !imageUrl.startsWith('https://')) {
      final baseUrl = AppConfig.baseUrl.endsWith('/')
          ? AppConfig.baseUrl.substring(0, AppConfig.baseUrl.length - 1)
          : AppConfig.baseUrl;
      final relativePath = imageUrl.startsWith('/') ? imageUrl : '/$imageUrl';
      fullUrl = '$baseUrl$relativePath';
    }

    return CachedNetworkImage(
      imageUrl: fullUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: Container(
        color: CupertinoColors.systemGrey5,
        child: const Center(
          child: CupertinoActivityIndicator(),
        ),
      ),
      errorWidget: Container(
        color: CupertinoColors.systemGrey5,
        child: const Center(
          child: Icon(
            CupertinoIcons.photo,
            size: 48,
            color: CupertinoColors.systemGrey,
          ),
        ),
      ),
    );
  }
}
