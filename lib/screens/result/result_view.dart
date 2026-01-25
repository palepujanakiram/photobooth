import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'transformed_image_model.dart';
import 'result_viewmodel.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';
import '../../views/widgets/app_theme.dart';
import '../../views/widgets/full_screen_loader.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  TextEditingController? _printerIpController;
  final GlobalKey _shareButtonKey = GlobalKey();
  ResultViewModel? _resultViewModel;
  bool _isInitialized = false;

  @override
  void dispose() {
    _printerIpController?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isInitialized) return;

    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args == null) return;

    final transformedImage = args['transformedImage'] as TransformedImageModel?;
    final transformationTime = args['transformationTime'] as int?;

    if (transformedImage == null) {
      return;
    }

    _resultViewModel = ResultViewModel(
      transformedImage: transformedImage,
      transformationTime: transformationTime,
    );
    _printerIpController ??=
        TextEditingController(text: _resultViewModel!.printerIp);
    _isInitialized = true;

  }

  /// Get the position of the share button for iOS share sheet positioning
  Rect? _getShareButtonPosition() {
    try {
      final RenderBox? renderBox =
          _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final position = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;
        return Rect.fromLTWH(
          position.dx,
          position.dy,
          size.width,
          size.height,
        );
      }
    } catch (e) {
      AppLogger.warning('Failed to get share button position: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        body: Center(child: CupertinoActivityIndicator()),
      );
    }

    if (_resultViewModel == null) {
      return const Scaffold(
        body: Center(child: Text('No transformed image available')),
      );
    }

    return ChangeNotifierProvider.value(
      value: _resultViewModel!,
      child: Stack(
        children: [
          CupertinoPageScaffold(
            navigationBar: const AppTopBar(
              title: 'Result',
            ),
            child: SafeArea(
              child: Consumer<ResultViewModel>(
                builder: (context, viewModel, child) {
                  final imageUrl = viewModel.imageUrl;

                  if (_printerIpController != null &&
                      _printerIpController!.text != viewModel.printerIp) {
                    _printerIpController!.text = viewModel.printerIp;
                  }

                  return Column(
                    children: [
                  // Show transformation time badge
                  if (viewModel.transformationTime != null)
                    Container(
                      margin: const EdgeInsets.only(top: 16, bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGreen.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: CupertinoColors.systemGreen.withValues(alpha: 0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            CupertinoIcons.checkmark_alt_circle_fill,
                            color: CupertinoColors.systemGreen,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Completed in ${viewModel.formattedTransformationTime}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: CupertinoColors.systemGreen,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: Center(
                      child: imageUrl != null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Image.network(
                                    imageUrl,
                                    fit: BoxFit.contain,
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                      if (loadingProgress == null) {
                                        return child;
                                      }
                                      return const Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          CupertinoActivityIndicator(),
                                          SizedBox(height: 16),
                                          Text(
                                            'Loading image...',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color:
                                                  CupertinoColors.systemGrey,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                    errorBuilder:
                                        (context, error, stackTrace) {
                                      AppLogger.debug(
                                          '❌ Image.network error: $error');
                                      return Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            CupertinoIcons
                                                .exclamationmark_triangle,
                                            size: 64,
                                            color:
                                                CupertinoColors.systemRed,
                                          ),
                                          const SizedBox(height: 16),
                                          const Text(
                                            'Failed to load image',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color:
                                                  CupertinoColors.systemRed,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                if (viewModel.needsDownload) ...[
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Image will download when you share/print',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: CupertinoColors.systemGrey2,
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  CupertinoIcons.photo,
                                  size: 64,
                                  color: CupertinoColors.systemGrey,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Image file not found',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: CupertinoColors.systemGrey,
                                  ),
                                ),
                                if (viewModel.transformedImage != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Image ID: ${viewModel.transformedImage!.id}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: CupertinoColors.systemGrey2,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ),
                  if (viewModel.hasError)
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        viewModel.errorMessage ?? 'Unknown error',
                        style: const TextStyle(
                          color: CupertinoColors.systemRed,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          // Printer IP input field and silent print button row
                          Row(
                            children: [
                              Expanded(
                                child: CupertinoTextField(
                                  placeholder: 'Printer IP',
                                  controller: _printerIpController,
                                  onChanged: (value) {
                                    viewModel.setPrinterIp(value);
                                  },
                                  keyboardType: TextInputType.number,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.systemGrey6,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 50,
                                height: 44,
                                child: CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  color: CupertinoColors.systemBlue,
                                  borderRadius: BorderRadius.circular(8),
                                  onPressed: viewModel.isSilentPrinting || viewModel.isDownloading
                                      ? null
                                      : () async {
                                          await viewModel.silentPrintToNetwork();
                                        },
                                  child: viewModel.isSilentPrinting
                                      ? const CupertinoActivityIndicator(
                                          color: CupertinoColors.white,
                                        )
                                      : const Icon(
                                          CupertinoIcons.printer_fill,
                                          color: CupertinoColors.white,
                                          size: 20,
                                        ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          AppButtonWithIcon(
                            text: 'Print',
                            icon: CupertinoIcons.printer_fill,
                            onPressed: viewModel.isDialogPrinting || viewModel.isDownloading
                                ? null
                                : () async {
                                    await viewModel.printImage();
                                  },
                            isLoading: viewModel.isDialogPrinting,
                          ),
                          const SizedBox(height: 12),
                          AppButtonWithIcon(
                            key: _shareButtonKey,
                            text: 'Share via WhatsApp',
                            icon: CupertinoIcons.share,
                            onPressed: viewModel.isSharing || viewModel.isDownloading
                                ? null
                                : () async {
                                    final sharePosition = _getShareButtonPosition();
                                    await viewModel.shareViaWhatsApp(
                                      sharePositionOrigin: sharePosition,
                                    );
                                  },
                            isLoading: viewModel.isSharing,
                          ),
                          const SizedBox(height: 12),
                          AppOutlinedButton(
                            text: 'Start Over',
                            icon: CupertinoIcons.house_fill,
                            onPressed: () {
                              Navigator.pushNamedAndRemoveUntil(
                                context,
                                AppConstants.kRouteCapture,
                                (route) => false,
                              );
                            },
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
          Consumer<ResultViewModel>(
            builder: (context, viewModel, child) {
              if (viewModel.isDownloading) {
                return Positioned.fill(
                  child: FullScreenLoader(
                    text: 'Preparing Result',
                    subtitle: 'Downloading generated image',
                    currentProcess: viewModel.downloadMessage,
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
}

