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
  late ResultViewModel _resultViewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null) {
      final transformedImage = args['transformedImage'] as TransformedImageModel?;
      if (transformedImage != null) {
        _resultViewModel = ResultViewModel(transformedImage: transformedImage);
      }
    }
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

    _resultViewModel = ResultViewModel(transformedImage: transformedImage);

    return ChangeNotifierProvider.value(
      value: _resultViewModel,
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

