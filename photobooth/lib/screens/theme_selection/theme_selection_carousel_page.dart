import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../../views/widgets/theme_card.dart';
import 'theme_model.dart';
import 'theme_selection_viewmodel.dart';

/// Single carousel page in theme selection (Sonar S3776 extraction).
class ThemeSelectionCarouselPage extends StatelessWidget {
  const ThemeSelectionCarouselPage({
    super.key,
    required this.theme,
    required this.index,
    required this.pageController,
    required this.viewModel,
    required this.fallbackCarouselIndex,
    required this.addOneMoreStyle,
    required this.usedThemeIds,
    required this.onTap,
    required this.onPreview,
  });

  final ThemeModel theme;
  final int index;
  final PageController pageController;
  final ThemeViewModel viewModel;
  final int fallbackCarouselIndex;
  final bool addOneMoreStyle;
  final List<String> usedThemeIds;
  final VoidCallback onTap;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final isSelected = viewModel.selectedTheme?.id == theme.id;
    return AnimatedBuilder(
      animation: pageController,
      builder: (context, _) {
        final hasPage = pageController.position.hasContentDimensions &&
            pageController.page != null;
        final page =
            hasPage ? pageController.page! : fallbackCarouselIndex.toDouble();
        final offset = page - index;
        final delta = offset.abs();
        final scale = (1.0 - (delta * 0.28)).clamp(0.48, 1.15);
        final opacity = (1.0 - (delta * 0.22)).clamp(0.5, 1.0);
        final isCenter = delta < 0.5;
        const perspective = 0.001;
        final angleY = offset * 0.5;
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, perspective)
          ..rotateY(angleY)
          ..scaleByDouble(scale, scale, 1.0, 1.0);
        final aspectRatio = isCenter
            ? AppConstants.themeCardSlotAspectRatio(context)
            : AppConstants.themeCarouselSideAspectRatio(context);
        return Opacity(
          opacity: opacity,
          child: Transform(
            alignment: Alignment.center,
            transform: matrix,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
              child: Center(
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 40,
                          offset: const Offset(0, 20),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ThemeCard(
                      theme: theme,
                      isSelected: isSelected,
                      selectedBorderWidth: isSelected &&
                              viewModel.armedTheme?.id == theme.id
                          ? 4.0
                          : 2.0,
                      onTap: onTap,
                      onPreview: onPreview,
                      showSelectedLabel:
                          addOneMoreStyle && usedThemeIds.contains(theme.id),
                      onSelectPressed: null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
