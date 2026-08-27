import 'app_strings.dart';
import 'classic_shot_mode.dart';

/// One Classic mode card on the shot-choice preview screen.
class ClassicShotChoiceOption {
  const ClassicShotChoiceOption({
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.previewAsset,
    required this.badge,
    required this.startLabel,
  });

  final ClassicShotMode mode;
  final String title;
  final String subtitle;
  final String previewAsset;
  final String badge;
  final String startLabel;
}

/// Builds preview cards for each kiosk-enabled Classic shot count (1 / 3 / 4).
List<ClassicShotChoiceOption> classicShotChoiceOptions(List<int> modes) {
  final out = <ClassicShotChoiceOption>[];
  if (modes.contains(4)) {
    out.add(
      const ClassicShotChoiceOption(
        mode: ClassicShotMode.fourShot,
        title: AppStrings.experienceClassicFourShot,
        subtitle: AppStrings.classicShotChoiceFourSubtitle,
        previewAsset: AppStrings.experienceClassicPreviewAsset,
        badge: AppStrings.experienceClassicFourShotPreviewBadge,
        startLabel: AppStrings.experienceClassicStartFourShot,
      ),
    );
  }
  if (modes.contains(3)) {
    out.add(
      const ClassicShotChoiceOption(
        mode: ClassicShotMode.threeShot,
        title: AppStrings.experienceClassicThreeShot,
        subtitle: AppStrings.classicShotChoiceThreeSubtitle,
        previewAsset: AppStrings.experienceClassicThreeShotPreviewAsset,
        badge: AppStrings.experienceClassicThreeShotPreviewBadge,
        startLabel: AppStrings.experienceClassicStartThreeShot,
      ),
    );
  }
  if (modes.contains(1)) {
    out.add(
      const ClassicShotChoiceOption(
        mode: ClassicShotMode.single6x4,
        title: AppStrings.experienceClassicOneShot,
        subtitle: AppStrings.classicShotChoiceOneSubtitle,
        previewAsset: AppStrings.experienceClassicOneShotPreviewAsset,
        badge: AppStrings.experienceClassicOneShotPreviewBadge,
        startLabel: AppStrings.experienceClassicStartOneShot,
      ),
    );
  }
  return out;
}

/// True when guests should pick a mode on a dedicated preview screen.
bool classicShotChoiceUsesPreviewScreen(List<int> modes) => modes.length > 1;
