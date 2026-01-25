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
  PhotoModel? _photo;
  ThemeModel? _theme;
  Future<List<int>>? _photoBytesFuture;
  bool _isInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInitialized) return;
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args == null) return;
    final photo = args['photo'] as PhotoModel?;
    final theme = args['theme'] as ThemeModel?;
    if (photo != null && theme != null) {
      _photo = photo;
      _theme = theme;
      _reviewViewModel = ReviewViewModel(photo: photo, theme: theme);
      _photoBytesFuture = photo.imageFile.readAsBytes();
      _isInitialized = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _photo == null || _theme == null) {
      return const Scaffold(
        body: Center(child: CupertinoActivityIndicator()),
      );
    }

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
                                            future: _photoBytesFuture,
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
                                          child: _theme?.sampleImageUrl !=
                                                      null &&
                                                  _theme!
                                                      .sampleImageUrl!
                                                      .isNotEmpty
                                              ? _buildThemeImage(
                                                  _theme!.sampleImageUrl!,
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
                                                        _theme?.name ??
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
                                                          _theme
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
                        // Button section (error shown in snackbar instead)

                        Padding(
                          padding: EdgeInsets.only(
                            bottom: 16.0 + bottomPadding,
                          ),
                          child: Consumer<ReviewViewModel>(
                            builder: (context, viewModel, child) {
                              return AppContinueButton(
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
                                              'transformationTime': viewModel.elapsedSeconds,
                                            },
                                          );
                                        } else if (viewModel.hasError) {
                                          // Show detailed error in dialog
                                          final errorMessage =
                                              viewModel.errorMessage ??
                                                  'Unknown error';
                                          
                                          // Show error with full details
                                          AppSnackBar.showError(
                                            currentContext,
                                            errorMessage,
                                          );
                                        }
                                      },
                                isLoading: viewModel.isTransforming,
                                padding: EdgeInsets.zero,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          // Full screen loader overlay with timer - positioned to cover entire screen
          Consumer<ReviewViewModel>(
            builder: (context, viewModel, child) {
              if (viewModel.isTransforming) {
                return Positioned.fill(
                  child: FullScreenLoader(
                    text: 'Generating AI Image',
                    loaderColor: CupertinoColors.systemBlue,
                    elapsedSeconds: viewModel.elapsedSeconds,
                    hint: 'Note: It may take up to a couple of minutes. Please be patient.',
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
