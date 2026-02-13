import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Colors;
import 'package:provider/provider.dart';
import 'result_viewmodel.dart';
import '../photo_generate/photo_generate_viewmodel.dart';
import '../photo_capture/photo_model.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_theme.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';

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
      return CupertinoPageScaffold(
        backgroundColor: appColors.backgroundColor,
        child: const Center(child: CupertinoActivityIndicator()),
      );
    }

    return ChangeNotifierProvider.value(
      value: _viewModel!,
      child: Consumer<ResultViewModel>(
        builder: (context, viewModel, child) {
          return CupertinoPageScaffold(
            backgroundColor: appColors.backgroundColor,
            navigationBar: AppTopBar(
              title: 'Pay & Collect',
              leading: AppActionButton(
                icon: CupertinoIcons.back,
                onPressed: () => Navigator.pop(context),
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  // Step banner
                  _buildStepBanner(context, 3), // 3 = Pay & Collect step
                  
                  // Main content
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          // Title section
                          _buildTitleSection(appColors),
                          const SizedBox(height: 24),
                          
                          // Main content - Photos and Payment
                          _buildMainContent(context, viewModel, appColors),
                          
                          const SizedBox(height: 24),
                          
                          // Info text
                          Text(
                            'Payment will be verified automatically. Print will start once payment is approved.',
                            style: TextStyle(
                              fontSize: 13,
                              color: appColors.secondaryTextColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          
                          const SizedBox(height: 24),
                          
                          // Print/Share actions section
                          _buildPrintShareSection(context, viewModel, appColors),
                          
                          // Error message
                          if (viewModel.hasError)
                            Container(
                              margin: const EdgeInsets.only(top: 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: CupertinoColors.systemRed.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    CupertinoIcons.exclamationmark_triangle,
                                    color: CupertinoColors.systemRed,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      viewModel.errorMessage!,
                                      style: const TextStyle(
                                        color: CupertinoColors.systemRed,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  CupertinoButton(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    onPressed: () => viewModel.clearError(),
                                    child: const Icon(
                                      CupertinoIcons.xmark,
                                      color: CupertinoColors.systemRed,
                                      size: 18,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Bottom buttons
                  _buildBottomButtons(context, viewModel, appColors),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

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

  Widget _buildTitleSection(AppColors appColors) {
    return Column(
      children: [
        Text(
          'Complete Payment',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: appColors.textColor,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Scan the QR code to pay and print',
          style: TextStyle(
            fontSize: 16,
            color: appColors.secondaryTextColor,
          ),
        ),
      ],
    );
  }

  Widget _buildMainContent(BuildContext context, ResultViewModel viewModel, AppColors appColors) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 600;
    
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
      // Single column layout for narrow screens
      return Column(
        children: [
          _buildPhotosSection(viewModel, appColors),
          const SizedBox(height: 24),
          _buildPaymentCard(viewModel, appColors),
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
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: appColors.textColor,
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
          color: CupertinoColors.systemBlue,
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
                    child: CupertinoActivityIndicator(),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                color: appColors.surfaceColor,
                child: const Center(
                  child: Icon(
                    CupertinoIcons.photo,
                    size: 32,
                    color: CupertinoColors.systemGrey,
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
                color: CupertinoColors.systemBlue,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$number',
                  style: const TextStyle(
                    color: CupertinoColors.white,
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: appColors.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: appColors.borderColor),
        boxShadow: [
          BoxShadow(
            color: appColors.shadowColor.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Price
          Text(
            'Rs $totalPrice',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: appColors.textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            photoCount > 1
                ? '$photoCount prints: Rs $basePrice + ${photoCount - 1} x Rs $additionalPrice'
                : '1 print: Rs $basePrice',
            style: TextStyle(
              fontSize: 13,
              color: appColors.secondaryTextColor,
            ),
          ),
          const SizedBox(height: 20),
          
          // QR Code placeholder
          Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              color: CupertinoColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: appColors.borderColor),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.qrcode,
                  size: 100,
                  color: appColors.textColor,
                ),
                const SizedBox(height: 8),
                Text(
                  'QR Code',
                  style: TextStyle(
                    fontSize: 12,
                    color: appColors.secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // UPI info
          Text(
            'UPI Payment',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: appColors.textColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Scan with any UPI app (GPay, PhonePe, Paytm, etc.)',
            style: TextStyle(
              fontSize: 12,
              color: appColors.secondaryTextColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Trusted by 10,000+ happy visitors',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: CupertinoColors.systemBlue,
            ),
          ),
          const SizedBox(height: 16),
          
          // Waiting status
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CupertinoActivityIndicator(radius: 8),
              const SizedBox(width: 8),
              Text(
                'Waiting for payment confirmation...',
                style: TextStyle(
                  fontSize: 13,
                  color: appColors.secondaryTextColor,
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
        color: appColors.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: appColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Section title
          Text(
            'Print & Share Options',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: appColors.textColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          
          // Printer IP TextField
          Row(
            children: [
              Text(
                'Printer IP:',
                style: TextStyle(
                  fontSize: 14,
                  color: appColors.textColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CupertinoTextField(
                  placeholder: '192.168.2.108',
                  controller: _printerIpController,
                  onChanged: (value) => viewModel.setPrinterIp(value),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: appColors.backgroundColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: appColors.borderColor),
                  ),
                  style: TextStyle(
                    color: appColors.textColor,
                    fontSize: 14,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Silent Print button
          CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 14),
            color: CupertinoColors.systemGreen,
            borderRadius: BorderRadius.circular(10),
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
                      const CupertinoActivityIndicator(color: CupertinoColors.white),
                      const SizedBox(width: 8),
                      Text(
                        viewModel.isDownloadingForSilentPrint ? viewModel.downloadMessage : 'Printing...',
                        style: const TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.printer,
                        color: CupertinoColors.white,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Silent Print (Network)',
                        style: TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          
          // Print with Dialog and Share buttons row
          Row(
            children: [
              // Print with Dialog button
              Expanded(
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  color: CupertinoColors.systemBlue,
                  borderRadius: BorderRadius.circular(10),
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
                            CupertinoActivityIndicator(color: CupertinoColors.white),
                            SizedBox(width: 8),
                            Text(
                              'Preparing...',
                              style: TextStyle(
                                color: CupertinoColors.white,
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
                              color: CupertinoColors.white,
                              size: 16,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Print',
                              style: TextStyle(
                                color: CupertinoColors.white,
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
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  color: CupertinoColors.systemOrange,
                  borderRadius: BorderRadius.circular(10),
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
                            CupertinoActivityIndicator(color: CupertinoColors.white),
                            SizedBox(width: 8),
                            Text(
                              'Preparing...',
                              style: TextStyle(
                                color: CupertinoColors.white,
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
                              color: CupertinoColors.white,
                              size: 16,
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Share',
                              style: TextStyle(
                                color: CupertinoColors.white,
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appColors.backgroundColor,
        boxShadow: [
          BoxShadow(
            color: appColors.shadowColor.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 12),
        onPressed: () {
          _showDeleteConfirmation(context, viewModel, appColors);
        },
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.trash,
              size: 16,
              color: CupertinoColors.systemRed,
            ),
            SizedBox(width: 8),
            Text(
              'Delete My Data Now',
              style: TextStyle(
                fontSize: 14,
                color: CupertinoColors.systemRed,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, ResultViewModel viewModel, AppColors appColors) {
    showCupertinoDialog(
      context: context,
      builder: (dialogContext) {
        return CupertinoAlertDialog(
          title: const Text('Delete My Data'),
          content: const Text(
            'This will delete all your photos and generated images. This action cannot be undone.',
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(dialogContext);
                // Navigate to terms screen and clear all data
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  AppConstants.kRouteTerms,
                  (route) => false,
                );
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}

/// Helper class to store step information
class _StepInfo {
  final IconData icon;
  final String label;

  _StepInfo({required this.icon, required this.label});
}
