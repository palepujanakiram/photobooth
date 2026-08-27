import 'dart:async';

import 'package:flutter/material.dart';

import '../../utils/app_strings.dart';
import '../../utils/classic_shot_choice_options.dart';
import '../../utils/classic_shot_mode.dart';
import '../../utils/constants.dart';
import '../../utils/fotoflashback_navigation.dart';
import '../../utils/route_args.dart';
import '../../views/widgets/animated_slideshow_background.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/centered_max_width.dart';
import '../theme_selection/theme_model.dart';
import 'classic_shot_choice_view_widgets.dart';

/// After Classic on experience choice: pick 1 / 3 / 4 with sample previews.
class ClassicShotChoiceScreen extends StatelessWidget {
  const ClassicShotChoiceScreen({
    super.key,
    required this.theme,
    required this.modes,
  });

  final ThemeModel theme;
  final List<int> modes;

  factory ClassicShotChoiceScreen.fromRouteArgs(Object? raw) {
    final args = ClassicShotChoiceArgs.tryParse(raw);
    return ClassicShotChoiceScreen(
      theme: args?.theme ??
          const ThemeModel(
            id: '',
            categoryId: '',
            name: '',
            description: '',
            promptText: '',
          ),
      modes: args?.modes ?? const [1, 3, 4],
    );
  }

  Future<void> _start(BuildContext context, ClassicShotMode mode) async {
    if (theme.id.isEmpty) return;
    await navigateToFotoFlashbackCapture(
      context: context,
      theme: theme,
      replace: true,
      shotMode: mode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final options = classicShotChoiceOptions(modes);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      backgroundColor: appColors.backgroundColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const IgnorePointer(
            child: Opacity(
              opacity: 0.35,
              child: AnimatedSlideshowBackground(),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xE6101014),
                    Color(0xF2101014),
                    Color(0xF5101014),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushReplacementNamed(
                        AppConstants.kRouteExperienceChoice,
                      );
                    },
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 16,
                      color: appColors.secondaryTextColor,
                    ),
                    label: Text(
                      AppStrings.classicShotChoiceBack,
                      style: TextStyle(
                        color: appColors.secondaryTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                  child: Column(
                    children: [
                      Text(
                        AppStrings.classicShotChoiceTitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: appColors.textColor,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppStrings.classicShotChoiceSubtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: appColors.secondaryTextColor,
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CenteredMaxWidth(
                    maxWidth: wide ? 980 : 640,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: _ClassicShotChoiceBody(
                        options: options,
                        wide: wide,
                        emptyColor: appColors.secondaryTextColor,
                        onStart: (mode) => unawaited(_start(context, mode)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClassicShotChoiceBody extends StatelessWidget {
  const _ClassicShotChoiceBody({
    required this.options,
    required this.wide,
    required this.emptyColor,
    required this.onStart,
  });

  final List<ClassicShotChoiceOption> options;
  final bool wide;
  final Color emptyColor;
  final void Function(ClassicShotMode mode) onStart;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) {
      return Center(
        child: Text(
          AppStrings.experienceFotoFlashUnavailable,
          style: TextStyle(color: emptyColor),
        ),
      );
    }
    if (wide && options.length > 1) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 16),
            Expanded(
              child: ClassicShotPreviewCard(
                option: options[i],
                onTap: () => onStart(options[i].mode),
              ),
            ),
          ],
        ],
      );
    }
    return ListView.separated(
      itemCount: options.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (context, i) {
        return SizedBox(
          height: 420,
          child: ClassicShotPreviewCard(
            option: options[i],
            onTap: () => onStart(options[i].mode),
          ),
        );
      },
    );
  }
}
