import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'result_viewmodel.dart';
import '../photo_generate/photo_generate_viewmodel.dart';
import '../photo_capture/photo_model.dart';
import '../../utils/constants.dart';
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
  late TextEditingController _printerIpController;

  @override
  void initState() {
    super.initState();
    _printerIpController = TextEditingController();
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
    );
    _printerIpController.text = _viewModel!.printerIp;
    _isInitialized = true;
  }

  @override
  void dispose() {
    _printerIpController.dispose();
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
      child: Consumer<ResultViewModel>(
        builder: (context, viewModel, child) {
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
                                      const SizedBox(height: 20),
                                      _buildPrintShareSection(context, viewModel, appColors),
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
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildTitleSection(appColors),
                                  const SizedBox(height: 16),
                                  _buildPaymentCard(viewModel, appColors),
                                ],
                              ),
                            ),
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Column(
                                  children: [
                                    _buildPhotosSection(viewModel, appColors),
                                    const SizedBox(height: 20),
                                    _buildPrintShareSection(context, viewModel, appColors),
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
            child: _buildPaymentCard(viewModel, appColors),
          ),
        ],
      );
    } else {
      // Single column: payment card (with QR) first so QR is visible without scrolling
      return Column(
        children: [
          _buildPaymentCard(viewModel, appColors),
          const SizedBox(height: 24),
          _buildPhotosSection(viewModel, appColors),
        ],
      );
    }
  }

  Widget _buildPhotosSection(ResultViewModel viewModel, AppColors appColors) {
    final photoCount = viewModel.generatedImages.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Your $photoCount Photo${photoCount > 1 ? 's' : ''}',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.center,
          children: List.generate(viewModel.generatedImages.length, (index) {
            final image = viewModel.generatedImages[index];
            return _buildPhotoCard(image, index + 1, appColors);
          }),
        ),
      ],
    );
  }

  Widget _buildPhotoCard(GeneratedImage image, int number, AppColors appColors) {
    return Container(
      width: 140,
      height: 180,
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

  Widget _buildPaymentCard(ResultViewModel viewModel, AppColors appColors) {
    final photoCount = viewModel.generatedImages.length;
    const basePrice = 100;
    const additionalPrice = 50;
    final totalPrice = basePrice + (photoCount > 1 ? (photoCount - 1) * additionalPrice : 0);
    
    return Container(
      clipBehavior: Clip.none,
      padding: const EdgeInsets.all(16),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Rs $totalPrice',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            photoCount > 1
                ? '$photoCount prints: Rs $basePrice + ${photoCount - 1} x Rs $additionalPrice'
                : '1 print: Rs $basePrice',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final side = (constraints.maxWidth - 32).clamp(120.0, 160.0);
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
                      size: 100,
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
          const SizedBox(height: 12),
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
          const SizedBox(height: 6),
          const Text(
            'Trusted by 10,000+ happy visitors',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              const SizedBox(width: 8),
              Text(
                'Waiting for payment confirmation...',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ],
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
                'Printer IP:',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _printerIpController,
                  onChanged: (value) => viewModel.setPrinterIp(value),
                  decoration: InputDecoration(
                    hintText: '192.168.2.108',
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
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ],
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
    // Hidden for now; re-enable by returning the Container with the delete button
    return const SizedBox.shrink();
  }

  // ignore: unused_element - used when delete button is re-enabled
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
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  AppConstants.kRouteTerms,
                  (route) => false,
                );
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
}
