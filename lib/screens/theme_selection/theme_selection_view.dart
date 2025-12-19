import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_selection_viewmodel.dart';
import '../../utils/constants.dart';
import '../../views/widgets/theme_card.dart';

class ThemeSelectionScreen extends StatefulWidget {
  const ThemeSelectionScreen({super.key});

  @override
  State<ThemeSelectionScreen> createState() => _ThemeSelectionScreenState();
}

class _ThemeSelectionScreenState extends State<ThemeSelectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ThemeViewModel>().loadThemes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > AppConstants.kTabletBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Theme'),
        centerTitle: true,
      ),
      body: Consumer<ThemeViewModel>(
        builder: (context, viewModel, child) {
          if (viewModel.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (viewModel.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    viewModel.errorMessage ?? 'Unknown error',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => viewModel.loadThemes(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (viewModel.themes.isEmpty) {
            return const Center(
              child: Text('No themes available'),
            );
          }

          return GridView.builder(
            padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isTablet ? 3 : 2,
              crossAxisSpacing: 16.0,
              mainAxisSpacing: 16.0,
              childAspectRatio: 0.8,
            ),
            itemCount: viewModel.themes.length,
            itemBuilder: (context, index) {
              final theme = viewModel.themes[index];
              final isSelected = viewModel.selectedTheme?.id == theme.id;

              return ThemeCard(
                theme: theme,
                isSelected: isSelected,
                onTap: () {
                  viewModel.selectTheme(theme);
                  Navigator.pushNamed(
                    context,
                    AppConstants.kRouteCameraSelection,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

