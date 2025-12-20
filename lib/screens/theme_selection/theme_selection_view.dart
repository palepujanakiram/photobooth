import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'theme_selection_viewmodel.dart';
import '../../utils/constants.dart';
import '../../views/widgets/theme_card.dart';
import '../../views/widgets/app_theme.dart';
import '../../services/theme_manager.dart';

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
      final viewModel = context.read<ThemeViewModel>();
      // Use cached themes immediately if available (faster)
      final themeManager = ThemeManager();
      if (themeManager.hasThemes) {
        // Update themes from cache immediately
        viewModel.updateFromCache();
      }
      // Then fetch/refresh themes
      viewModel.loadThemes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > AppConstants.kTabletBreakpoint;

    return CupertinoPageScaffold(
      navigationBar: const AppTopBar(
        title: 'Select Theme',
      ),
      child: SafeArea(
        child: Consumer<ThemeViewModel>(
          builder: (context, viewModel, child) {
            if (viewModel.isLoading) {
              return const Center(
                child: CupertinoActivityIndicator(),
              );
            }

            if (viewModel.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      CupertinoIcons.exclamationmark_triangle,
                      size: 64,
                      color: CupertinoColors.systemRed,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      viewModel.errorMessage ?? 'Unknown error',
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    CupertinoButton(
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
                childAspectRatio: isTablet ? 0.75 : 0.7,
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
      ),
    );
  }
}
