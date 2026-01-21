import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'transformed_image_model.dart';
import 'result_viewmodel.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';
import '../../views/widgets/app_theme.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  TextEditingController? _printerIpController;

  @override
  void dispose() {
    _printerIpController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    TransformedImageModel? transformedImage;

    if (args != null) {
      transformedImage = args['transformedImage'] as TransformedImageModel?;
    }

    if (transformedImage == null) {
      return const Scaffold(
        body: Center(child: Text('No transformed image available')),
      );
    }

    final resultViewModel = ResultViewModel(transformedImage: transformedImage);
    
    // Initialize controller if not already initialized
    _printerIpController ??= TextEditingController(text: resultViewModel.printerIp);
    // Update controller text if view model IP changed
    if (_printerIpController!.text != resultViewModel.printerIp) {
      _printerIpController!.text = resultViewModel.printerIp;
    }

    return ChangeNotifierProvider.value(
      value: resultViewModel,
      child: CupertinoPageScaffold(
        navigationBar: AppTopBar(
          title: 'Result',
          actions: [
            AppActionButton(
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
        child: SafeArea(
          child: Consumer<ResultViewModel>(
            builder: (context, viewModel, child) {
              final imageFile = viewModel.transformedImage?.imageFile;
              
              return Column(
                children: [
                  Expanded(
                    child: Center(
                      child: imageFile != null
                          ? FutureBuilder<Uint8List>(
                              future: imageFile.readAsBytes().catchError((error) {
                                AppLogger.debug('❌ Error reading image file: $error');
                                AppLogger.debug('   File path: ${imageFile.path}');
                                return Uint8List(0);
                              }),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState == ConnectionState.waiting) {
                                  return const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CupertinoActivityIndicator(),
                                      SizedBox(height: 16),
                                      Text(
                                        'Loading image...',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: CupertinoColors.systemGrey,
                                        ),
                                      ),
                                    ],
                                  );
                                }
                                if (snapshot.hasError || !snapshot.hasData || (snapshot.data?.isEmpty ?? true)) {
                                  return Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        CupertinoIcons.exclamationmark_triangle,
                                        size: 64,
                                        color: CupertinoColors.systemRed,
                                      ),
                                      const SizedBox(height: 16),
                                      const Text(
                                        'Failed to load image',
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: CupertinoColors.systemRed,
                                        ),
                                      ),
                                      if (snapshot.hasError) ...[
                                        const SizedBox(height: 8),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 32.0),
                                          child: Text(
                                            'Error: ${snapshot.error}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: CupertinoColors.systemGrey,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 32.0),
                                        child: Text(
                                          'Path: ${imageFile.path}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: CupertinoColors.systemGrey2,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ],
                                  );
                                }
                                return Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    AppLogger.debug('❌ Image.memory error: $error');
                                    return Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(
                                          CupertinoIcons.exclamationmark_triangle,
                                          size: 64,
                                          color: CupertinoColors.systemRed,
                                        ),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Failed to display image',
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: CupertinoColors.systemRed,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Error: $error',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: CupertinoColors.systemGrey,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
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
                                  onPressed: viewModel.isPrinting
                                      ? null
                                      : () async {
                                          await viewModel.silentPrintToNetwork();
                                        },
                                  child: viewModel.isPrinting
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
                            onPressed: viewModel.isPrinting
                                ? null
                                : () async {
                                    await viewModel.printImage();
                                  },
                            isLoading: viewModel.isPrinting,
                          ),
                          const SizedBox(height: 12),
                          AppButtonWithIcon(
                            text: 'Share via WhatsApp',
                            icon: CupertinoIcons.share,
                            onPressed: viewModel.isSharing
                                ? null
                                : () async {
                                    await viewModel.shareViaWhatsApp();
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
    );
  }
}

