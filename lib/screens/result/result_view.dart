import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'result_viewmodel.dart';
import '../photo_generate/photo_generate_viewmodel.dart';
import '../photo_capture/photo_model.dart';
import '../../services/app_settings_manager.dart';
import '../../utils/constants.dart';
import '../../utils/exceptions.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/leading_with_alice.dart';
import '../../views/widgets/theme_background.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  ResultViewModel? _viewModel;
  bool _isInitialized = false;
  late TextEditingController _printerHostController;

  @override
  void initState() {
    super.initState();
    _printerHostController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInitialized) return;

    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args == null) return;

    final generatedImages = args['generatedImages'] as List<GeneratedImage>?;
    final originalPhoto = args['originalPhoto'] as PhotoModel?;

    if (generatedImages == null || generatedImages.isEmpty) {
      return;
    }

    _viewModel = ResultViewModel(
      generatedImages: generatedImages,
      originalPhoto: originalPhoto,
      appSettingsManager: context.read<AppSettingsManager>(),
    );
    _printerHostController.text = _viewModel!.printerHost;
    _isInitialized = true;
  }

  @override
  void dispose() {
    _printerHostController.dispose();
    _viewModel?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);

    if (!_isInitialized || _viewModel == null) {
      return Scaffold(
        backgroundColor: appColors.backgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return ChangeNotifierProvider.value(
      value: _viewModel!,
      child: Consumer2<ResultViewModel, AppSettingsManager>(
        builder: (context, viewModel, _, child) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              forceMaterialTransparency: true,
              centerTitle: true,
              title: const Text(
                'Complete Payment',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                ),
              ),
              leading: IconButton(
                icon: const Icon(CupertinoIcons.back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              actions: const [AppBarAliceAction()],
            ),
            body: Stack(
              children: [
                const Positioned.fill(
                  child: ThemeBackground(),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: kToolbarHeight),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 600 ||
                            MediaQuery.orientationOf(context) == Orientation.landscape;
                        if (isWide) {
                          return Column(
                            children: [
                              Expanded(
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      _buildTitleSection(appColors),
                                      const SizedBox(height: 16),
                                      _buildMainContent(context, viewModel, appColors),
                                      if (AppConstants.kShowResultPrintSection) ...[
                                        const SizedBox(height: 20),
                                        _buildPrintShareSection(context, viewModel, appColors),
                                      ],
                                      if (viewModel.hasError) _buildErrorBanner(viewModel),
                                    ],
                                  ),
                                ),
                              ),
                              _buildBottomButtons(context, viewModel, appColors),
                            ],
                          );
                        }
                        // Narrow: title + payment card fixed at top so QR box is fully visible
                        return Column(
                          children: [
                            SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildTitleSection(appColors),
                                  const SizedBox(height: 16),
                                  _buildPaymentCard(context, viewModel, appColors),
                                ],
                              ),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Column(
                                  children: [
                                    _buildPhotosSection(viewModel, appColors),
                                    if (AppConstants.kShowResultPrintSection) ...[
                                      const SizedBox(height: 20),
                                      _buildPrintShareSection(context, viewModel, appColors),
                                    ],
                                    if (viewModel.hasError) _buildErrorBanner(viewModel),
                                  ],
                                ),
                              ),
                            ),
                            _buildBottomButtons(context, viewModel, appColors),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTitleSection(AppColors appColors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        'Payment will be verified automatically. Print will start once payment is approved.',
        style: TextStyle(
          fontSize: 13,
          color: Colors.white.withValues(alpha: 0.8),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildErrorBanner(ResultViewModel viewModel) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_triangle,
            color: Colors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              viewModel.errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => viewModel.clearError(),
            icon: const Icon(CupertinoIcons.xmark, color: Colors.red, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, ResultViewModel viewModel, AppColors appColors) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final isWideScreen = screenWidth > 600 || isLandscape;
    
    if (isWideScreen) {
      // Two column layout for wide screens
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side - Photos
          Expanded(
            flex: 1,
            child: _buildPhotosSection(viewModel, appColors),
          ),
          const SizedBox(width: 24),
          // Right side - Payment
          Expanded(
            flex: 1,
            child: _buildPaymentCard(context, viewModel, appColors),
          ),
        ],
      );
    } else {
      // Single column: payment card (with QR) first so QR is visible without scrolling
      return Column(
        children: [
          _buildPaymentCard(context, viewModel, appColors),
          const SizedBox(height: 24),
          _buildPhotosSection(viewModel, appColors),
        ],
      );
    }
  }

  static const double _photoCardAspectRatio = 140 / 180; // width / height
  static const double _photoCardSpacing = 12;

  /// Shared height for Pay & Collect and Your N Photos boxes so they align. Kept within typical viewport to avoid overflow.
  static const double _resultBoxHeight = 400;

  /// Space between title and QR box in payment card (title line + 4 + Rs row + 12). Match this in photos section so card tops align with QR top.
  static const double _resultBoxTitleToContentSpacing = 40;

  static const TextStyle _resultBoxTitleStyle = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    color: Colors.white,
  );

  Widget _buildPhotosSection(ResultViewModel viewModel, AppColors appColors) {
    final photoCount = viewModel.generatedImages.length;
    final images = viewModel.generatedImages;

    return Container(
      height: _resultBoxHeight,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Your $photoCount Photo${photoCount > 1 ? 's' : ''}',
            style: _resultBoxTitleStyle,
          ),
          const SizedBox(height: _resultBoxTitleToContentSpacing),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final innerWidth = constraints.maxWidth;
                final innerHeight = constraints.maxHeight;
                final spacingTotal = _photoCardSpacing * (images.length - 1);
                final n = images.length;
                // Size by width first, then constrain by available height to prevent overflow
                final cardWidthByWidth = (innerWidth - spacingTotal) / n;
                final cardHeightByWidth = cardWidthByWidth / _photoCardAspectRatio;
                final cardHeight = cardHeightByWidth.clamp(0.0, innerHeight);
                final cardWidth = cardHeight * _photoCardAspectRatio;
                return SizedBox(
                  height: cardHeight,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < n; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        SizedBox(
                          width: cardWidth,
                          height: cardHeight,
                          child: _buildPhotoCard(images[i], i + 1, appColors),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoCard(GeneratedImage image, int number, AppColors appColors) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.blue,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: appColors.shadowColor.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              image.imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Container(
                  color: appColors.surfaceColor,
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                color: appColors.surfaceColor,
                child: const Center(
                  child: Icon(
                    Icons.photo,
                    size: 32,
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
          ),
          // Number badge
          Positioned(
            top: 8,
            left: 8,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentCard(BuildContext context, ResultViewModel viewModel, AppColors appColors) {
    final photoCount = viewModel.generatedImages.length;
    final basePrice = viewModel.initialPrintPrice;
    final additionalPrice = viewModel.additionalPrintPrice;
    final totalPrice = viewModel.totalPrice;
    final breakdownText = photoCount > 1
        ? '$photoCount prints: Rs $basePrice + ${photoCount - 1} x Rs $additionalPrice'
        : '1 print: Rs $basePrice';

    return Container(
      height: _resultBoxHeight,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pay & Collect',
              style: _resultBoxTitleStyle,
            ),
            const SizedBox(height: 4),
            Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Rs $totalPrice',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  breakdownText,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final side = (constraints.maxWidth - 24).clamp(100.0, 130.0);
              return Container(
                width: side,
                height: side,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      CupertinoIcons.qrcode,
                      size: 72,
                      color: Colors.grey.shade700,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'QR Code',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'UPI Payment',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Scan with any UPI app (GPay, PhonePe, Paytm, etc.)',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.85),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const Text(
            'Trusted by 10,000+ happy visitors',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: viewModel.isSilentPrinting || viewModel.isDownloadingForSilentPrint || viewModel.isDialogPrinting || viewModel.isSharing
                      ? null
                      : () async {
                          await viewModel.silentPrintToNetwork();
                          if (viewModel.hasError && context.mounted) {
                            AppSnackBar.showError(context, viewModel.errorMessage!);
                          } else if (!viewModel.hasError && context.mounted) {
                            AppSnackBar.showSuccess(context, 'Print job sent successfully!');
                          }
                        },
                  child: viewModel.isSilentPrinting || viewModel.isDownloadingForSilentPrint
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                viewModel.isDownloadingForSilentPrint ? viewModel.downloadMessage : 'Printing...',
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.printer_fill, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Print',
                              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildDeleteButton(context, viewModel, appColors)),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildPrintShareSection(BuildContext context, ResultViewModel viewModel, AppColors appColors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Print & Share Options',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Printer:',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _printerHostController,
                  onChanged: (value) => viewModel.setPrinterHost(value),
                  decoration: InputDecoration(
                    hintText: AppConstants.kDefaultPrinterHost,
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.15),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                    ),
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                  keyboardType: TextInputType.url,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Print API port: ${viewModel.effectivePrinterPort}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 16),

          // Silent Print button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: viewModel.isSilentPrinting || viewModel.isDownloadingForSilentPrint || viewModel.isDialogPrinting || viewModel.isSharing
                  ? null
                  : () async {
                      await viewModel.silentPrintToNetwork();
                      if (viewModel.hasError && context.mounted) {
                        AppSnackBar.showError(context, viewModel.errorMessage!);
                      } else if (!viewModel.hasError && context.mounted) {
                        AppSnackBar.showSuccess(context, 'Print job sent successfully!');
                      }
                    },
              child: viewModel.isSilentPrinting || viewModel.isDownloadingForSilentPrint
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        viewModel.isDownloadingForSilentPrint ? viewModel.downloadMessage : 'Printing...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.printer_fill,
                        color: Colors.white,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Silent Print (Network)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Print with Dialog and Share buttons row
          Row(
            children: [
              // Print with Dialog button
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: viewModel.isDialogPrinting || viewModel.isDownloadingForDialogPrint || viewModel.isSilentPrinting || viewModel.isSharing
                      ? null
                      : () async {
                          await viewModel.printWithDialog();
                          if (viewModel.hasError && context.mounted) {
                            AppSnackBar.showError(context, viewModel.errorMessage!);
                          }
                        },
                  child: viewModel.isDialogPrinting || viewModel.isDownloadingForDialogPrint
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'Preparing...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.doc_text,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Print',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Share button
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: viewModel.isSharing || viewModel.isDownloadingForShare || viewModel.isSilentPrinting || viewModel.isDialogPrinting
                      ? null
                      : () async {
                          // Get button position for share sheet on iPad
                          final box = context.findRenderObject() as RenderBox?;
                          final sharePositionOrigin = box != null
                              ? box.localToGlobal(Offset.zero) & box.size
                              : null;
                          
                          await viewModel.shareImages(sharePositionOrigin: sharePositionOrigin);
                          if (viewModel.hasError && context.mounted) {
                            AppSnackBar.showError(context, viewModel.errorMessage!);
                          }
                        },
                  child: viewModel.isSharing || viewModel.isDownloadingForShare
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'Preparing...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.share,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Share',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
          
          // Help text
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'Silent Print sends directly to the network printer. Print opens system dialog.',
              style: TextStyle(
                fontSize: 11,
                color: appColors.secondaryTextColor,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons(BuildContext context, ResultViewModel viewModel, AppColors appColors) {
    return const SizedBox.shrink();
  }

  /// Delete my photos button, styled like the Print button (green, full width), placed below the content.
  Widget _buildDeleteButton(BuildContext context, ResultViewModel viewModel, AppColors appColors) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: () => _showDeleteConfirmation(context, viewModel, appColors),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.delete, color: Colors.white, size: 16),
            SizedBox(width: 6),
            Flexible(
              child: Text(
                'Delete my photos',
                style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, ResultViewModel viewModel, AppColors appColors) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete My Data'),
          content: const Text(
            'This will delete all your photos and generated images. This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await viewModel.deleteSession();
                  if (context.mounted) {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      AppConstants.kRouteTerms,
                      (route) => false,
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    AppSnackBar.showError(
                      context,
                      e is ApiException ? e.message : e.toString(),
                    );
                  }
                }
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
}
