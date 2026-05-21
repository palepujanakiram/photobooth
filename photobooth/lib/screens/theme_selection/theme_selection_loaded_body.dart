import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../views/widgets/app_snackbar.dart';
import 'theme_selection_viewmodel.dart';

/// Theme list states below the app bar (Sonar S3776 extraction).
class ThemeSelectionLoadedBody extends StatelessWidget {
  const ThemeSelectionLoadedBody({
    super.key,
    required this.viewModel,
    required this.mounted,
    required this.bottomPadding,
    required this.carousel,
  });

  final ThemeViewModel viewModel;
  final bool mounted;
  final double bottomPadding;
  final Widget carousel;

  @override
  Widget build(BuildContext context) {
    if (viewModel.showNoThemesMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (viewModel.showNoThemesMessage) {
          AppSnackBar.showError(context, 'No themes available');
          viewModel.clearNoThemesMessage();
        }
      });
    }
    if (viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (viewModel.hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              viewModel.errorMessage ?? 'Unknown error',
              style: const TextStyle(fontSize: 16, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => viewModel.loadThemes(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (viewModel.themes.isEmpty) {
      return const Center(
        child: Text(
          'No themes available',
          style: TextStyle(color: Colors.white),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Column(
        children: [
          Expanded(child: carousel),
        ],
      ),
    );
  }
}
