import 'dart:typed_data';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
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
import '../../views/widgets/bottom_safe_area.dart';
import '../../utils/route_args.dart';

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
    final parsed = GenerateArgs.tryParse(ModalRoute.of(context)?.settings.arguments);
    if (parsed == null) return;
    final photo = parsed.photo;
    final theme = parsed.theme;
    _photo = photo;
    _theme = theme;
    _reviewViewModel = ReviewViewModel(photo: photo, theme: theme);
    _photoBytesFuture = photo.imageFile.readAsBytes();
    _isInitialized = true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized || _photo == null || _theme == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return ChangeNotifierProvider.value(
      value: _reviewViewModel,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            appBar: const AppTopBar(
              title: 'Review Photo',
            ),
            body: SafeArea(
              top: true,
              bottom: false,
              child: BottomSafePadding(
                child: LayoutBuilder(
                builder: (context, constraints) {
                  final mediaQuery = MediaQuery.of(context);
                  final bottomPadding = mediaQuery.padding.bottom;
                  final isLandscape = mediaQuery.orientation == Orientation.landscape;
                  final contentPadding = isLandscape ? 10.0 : 16.0;
                  final labelFontSize = isLandscape ? 14.0 : 18.0;
                  final labelGap = isLandscape ? 6.0 : 12.0;
                  return Container(
                    width: double.infinity,
                    height: constraints.maxHeight,
                    color: Theme.of(context).colorScheme.surface,
                    padding: EdgeInsets.fromLTRB(contentPadding, contentPadding, contentPadding, 0.0),
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
                                    Text(
                                      'Captured Photo',
                                      style: TextStyle(
                                        fontSize: labelFontSize,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: labelGap),
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color:
                                              Theme.of(context).colorScheme.surfaceContainerHighest,
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
                                                      CircularProgressIndicator(),
                                                );
                                              }
                                              if (snapshot.hasError ||
                                                  !snapshot.hasData) {
                                                return Center(
                                                  child: Icon(
                                                    CupertinoIcons.exclamationmark_triangle,
                                                    color: Theme.of(context).colorScheme.error,
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
                              SizedBox(width: isLandscape ? 10 : 16),
                              // Right side: Selected Theme
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Selected Theme',
                                      style: TextStyle(
                                        fontSize: labelFontSize,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: labelGap),
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color:
                                              Theme.of(context).colorScheme.surfaceContainerHighest,
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
                                                  color: Colors.grey.shade300,
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      const Icon(
                                                        CupertinoIcons.paintbrush,
                                                        size: 64,
                                                        color:
                                                            Colors.grey,
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
                        SizedBox(height: isLandscape ? 8 : 16),
                        // Button section (error shown in snackbar instead)

                        Padding(
                          padding: EdgeInsets.only(
                            bottom: (isLandscape ? 10.0 : 16.0) + bottomPadding,
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
          ),
          // Full screen loader overlay with timer - positioned to cover entire screen
          Consumer<ReviewViewModel>(
            builder: (context, viewModel, child) {
              if (viewModel.isTransforming) {
                return Positioned.fill(
                  child: FullScreenLoader(
                    text: 'Generating AI Image',
                    loaderColor: Colors.blue,
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
        color: Colors.grey.shade300,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
      errorWidget: Container(
        color: Colors.grey.shade300,
        child: const Center(
          child: Icon(
            CupertinoIcons.photo,
            size: 48,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }
}
