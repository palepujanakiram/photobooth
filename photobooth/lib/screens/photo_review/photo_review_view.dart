import 'dart:typed_data';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../photo_capture/photo_model.dart';
import '../photo_generate/photo_generate_viewmodel.dart';
import '../theme_selection/theme_model.dart';
import 'photo_review_layout.dart';
import 'photo_review_viewmodel.dart';
import '../../utils/constants.dart';
import '../../utils/theme_image_urls.dart';
import '../../services/app_settings_manager.dart';
import '../../views/widgets/app_theme.dart';
import '../../views/widgets/full_screen_loader.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/cached_network_image.dart';
import '../../views/widgets/bottom_safe_area.dart';
import '../../utils/route_args.dart';
import '../../views/widgets/contact_before_pay_sheet.dart';
import '../../utils/secure_image_url.dart';

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
    _reviewViewModel = ReviewViewModel(
      photo: photo,
      theme: theme,
      appSettingsManager: context.read<AppSettingsManager>(),
    );
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
                  return _buildReviewBody(context, constraints);
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

  Widget _buildReviewBody(BuildContext context, BoxConstraints constraints) {
    final metrics = ReviewLayoutMetrics(
      isLandscape:
          MediaQuery.orientationOf(context) == Orientation.landscape,
    );
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Container(
      width: double.infinity,
      height: constraints.maxHeight,
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.fromLTRB(
        metrics.contentPadding,
        metrics.contentPadding,
        metrics.contentPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _buildCapturedPhotoPanel(context, metrics)),
                SizedBox(width: metrics.columnGap),
                Expanded(child: _buildThemePanel(context, metrics)),
              ],
            ),
          ),
          SizedBox(height: metrics.sectionGap),
          Padding(
            padding: EdgeInsets.only(
              bottom: metrics.bottomButtonPadding(bottomPadding),
            ),
            child: Consumer<ReviewViewModel>(
              builder: (context, viewModel, _) {
                return AppContinueButton(
                  text: 'Transform Photo',
                  onPressed: viewModel.isTransforming
                      ? null
                      : () => _handleTransformPhoto(context, viewModel),
                  isLoading: viewModel.isTransforming,
                  padding: EdgeInsets.zero,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapturedPhotoPanel(
    BuildContext context,
    ReviewLayoutMetrics metrics,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Captured Photo',
          style: TextStyle(
            fontSize: metrics.labelFontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: metrics.labelGap),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FutureBuilder<List<int>>(
                future: _photoBytesFuture,
                builder: (context, snapshot) =>
                    _buildPhotoBytesPreview(context, snapshot),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoBytesPreview(
    BuildContext context,
    AsyncSnapshot<List<int>> snapshot,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }
    if (snapshot.hasError || !snapshot.hasData) {
      return Center(
        child: Icon(
          CupertinoIcons.exclamationmark_triangle,
          color: Theme.of(context).colorScheme.error,
          size: 48,
        ),
      );
    }
    return Image.memory(
      Uint8List.fromList(snapshot.data!),
      fit: BoxFit.cover,
      width: double.infinity,
    );
  }

  Widget _buildThemePanel(BuildContext context, ReviewLayoutMetrics metrics) {
    final theme = _theme;
    final sampleUrl = theme?.sampleImageUrl?.trim() ?? '';
    final hasSample = sampleUrl.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Selected Theme',
          style: TextStyle(
            fontSize: metrics.labelFontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: metrics.labelGap),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: hasSample
                  ? _buildThemeImage(sampleUrl)
                  : _buildThemePlaceholder(theme),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThemePlaceholder(ThemeModel? theme) {
    return Container(
      color: Colors.grey.shade300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(CupertinoIcons.paintbrush, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            theme?.name ?? 'Unknown',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              theme?.description ?? '',
              style: const TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleTransformPhoto(
    BuildContext context,
    ReviewViewModel viewModel,
  ) async {
    final currentContext = context;
    final transformedImage = await viewModel.transformPhoto();

    if (!mounted || !currentContext.mounted) return;

    if (transformedImage != null) {
      final theme = viewModel.theme;
      final photo = viewModel.photo;
      if (theme == null || photo == null) return;

      final generated = GeneratedImage(
        id: transformedImage.id,
        // Persist auth in the URL so later loads don't 403 if the session is
        // cleared/expired during pay/print.
        imageUrl: SecureImageUrl.withSessionId(transformedImage.imageUrl),
        theme: theme,
        isSelected: true,
      );

      final contact = await showContactBeforePaySheet(currentContext);
      if (!mounted || !currentContext.mounted || contact == null) return;

      await Navigator.pushNamed(
        currentContext,
        AppConstants.kRouteResult,
        arguments: {
          'generatedImages': <GeneratedImage>[generated],
          'originalPhoto': photo,
          'customerName': contact.customerName,
          'customerPhone': contact.customerPhone,
          'customerWhatsappOptIn': contact.whatsappOptIn,
        },
      );
      return;
    }

    if (viewModel.hasError) {
      AppSnackBar.showError(
        currentContext,
        viewModel.errorMessage ?? 'Unknown error',
      );
    }
  }

  Widget _buildThemeImage(String imageUrl) {
    final fullUrl = resolveThemeSampleImageUrl(imageUrl);

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
