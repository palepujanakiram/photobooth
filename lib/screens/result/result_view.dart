import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'transformed_image_model.dart';
import 'result_viewmodel.dart';
import '../../utils/constants.dart';

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
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Result'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.home),
              onPressed: () {
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  AppConstants.kRouteHome,
                  (route) => false,
                );
              },
            ),
          ],
        ),
        body: SafeArea(
          child: Consumer<ResultViewModel>(
            builder: (context, viewModel, child) {
              final imageFile = viewModel.transformedImage?.imageFile;
              
              return Column(
                children: [
                  Expanded(
                    child: Center(
                      child: imageFile != null && imageFile.existsSync()
                          ? Image.file(
                              imageFile,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      size: 64,
                                      color: Colors.red,
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Failed to load image',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.red,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Path: ${imageFile.path}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                );
                              },
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.image_not_supported,
                                  size: 64,
                                  color: Colors.grey,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Image file not found',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                  ),
                                ),
                                if (imageFile != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Path: ${imageFile.path}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                    textAlign: TextAlign.center,
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
                          color: Colors.red,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          height: AppConstants.kButtonHeight,
                          child: ElevatedButton.icon(
                            onPressed: viewModel.isPrinting
                                ? null
                                : () async {
                                    await viewModel.printImage();
                                  },
                            icon: viewModel.isPrinting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.print),
                            label: const Text('Print'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: AppConstants.kButtonHeight,
                          child: ElevatedButton.icon(
                            onPressed: viewModel.isSharing
                                ? null
                                : () async {
                                    await viewModel.shareViaWhatsApp();
                                  },
                            icon: viewModel.isSharing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.share),
                            label: const Text('Share via WhatsApp'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: AppConstants.kButtonHeight,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pushNamedAndRemoveUntil(
                                context,
                                AppConstants.kRouteHome,
                                (route) => false,
                              );
                            },
                            icon: const Icon(Icons.home),
                            label: const Text('Start Over'),
                          ),
                        ),
                      ],
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

