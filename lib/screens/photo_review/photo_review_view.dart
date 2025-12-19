import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../photo_capture/photo_model.dart';
import '../theme_selection/theme_model.dart';
import 'photo_review_viewmodel.dart';
import '../../utils/constants.dart';

class PhotoReviewScreen extends StatefulWidget {
  const PhotoReviewScreen({super.key});

  @override
  State<PhotoReviewScreen> createState() => _PhotoReviewScreenState();
}

class _PhotoReviewScreenState extends State<PhotoReviewScreen> {
  late ReviewViewModel _reviewViewModel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null) {
      final photo = args['photo'] as PhotoModel?;
      final theme = args['theme'] as ThemeModel?;
      if (photo != null && theme != null) {
        _reviewViewModel = ReviewViewModel(photo: photo, theme: theme);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args == null) {
      return const Scaffold(
        body: Center(child: Text('Invalid arguments')),
      );
    }

    final photo = args['photo'] as PhotoModel?;
    final theme = args['theme'] as ThemeModel?;

    if (photo == null || theme == null) {
      return const Scaffold(
        body: Center(child: Text('Missing photo or theme')),
      );
    }

    _reviewViewModel = ReviewViewModel(photo: photo, theme: theme);

    return ChangeNotifierProvider.value(
      value: _reviewViewModel,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Review Photo'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Consumer<ReviewViewModel>(
            builder: (context, viewModel, child) {
              return Column(
                children: [
                  Expanded(
                    child: Center(
                      child: Image.file(
                        viewModel.photo!.imageFile,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text(
                          'Theme: ${viewModel.theme?.name ?? "Unknown"}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          viewModel.theme?.description ?? '',
                          style: const TextStyle(fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        if (viewModel.hasError)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: Text(
                              viewModel.errorMessage ?? 'Unknown error',
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 14,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        SizedBox(
                          width: double.infinity,
                          height: AppConstants.kButtonHeight,
                          child: ElevatedButton(
                            onPressed: viewModel.isTransforming
                                ? null
                                : () async {
                                    final transformedImage =
                                        await viewModel.transformPhoto();
                                    if (transformedImage != null &&
                                        mounted &&
                                        context.mounted) {
                                      Navigator.pushNamed(
                                        context,
                                        AppConstants.kRouteResult,
                                        arguments: {
                                          'transformedImage': transformedImage,
                                        },
                                      );
                                    }
                                  },
                            child: viewModel.isTransforming
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : const Text('Transform Photo'),
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

