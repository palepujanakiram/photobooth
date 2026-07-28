import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/kiosk_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/classic_shot_mode.dart';
import '../../utils/constants.dart';
import '../../utils/fotoflashback_navigation.dart';
import '../../utils/kiosk_page_route.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/animated_slideshow_background.dart';
import '../../views/widgets/centered_max_width.dart';
import '../photo_capture/photo_capture_view.dart';
import 'experience_choice_view_widgets.dart';
import 'experience_choice_viewmodel.dart';

/// After terms: guest picks FotoZen AI vs Classic 4-shot path.
class ExperienceChoiceScreen extends StatefulWidget {
  const ExperienceChoiceScreen({
    super.key,
    this.capturePrefillPhoto,
    this.kioskManager,
  });

  /// Optional POSE prefill (rare; forwarded from terms when present).
  final Object? capturePrefillPhoto;

  /// Injectable for tests; defaults to [KioskManager].
  final KioskManager? kioskManager;

  @override
  State<ExperienceChoiceScreen> createState() => _ExperienceChoiceScreenState();
}

class _ExperienceChoiceScreenState extends State<ExperienceChoiceScreen> {
  late final ExperienceChoiceViewModel _viewModel;
  late final KioskManager _kioskManager;
  bool _redirectingToAi = false;
  ClassicShotMode _classicShotMode = ClassicShotMode.fourShot;

  @override
  void initState() {
    super.initState();
    _kioskManager = widget.kioskManager ?? KioskManager();
    _viewModel = ExperienceChoiceViewModel();
    unawaited(_viewModel.load());
    unawaited(_redirectIfClassicDisabled());
  }

  /// Defensive: if Classic is off, skip this screen (deep link / stale route).
  Future<void> _redirectIfClassicDisabled() async {
    final classicEnabled = await _kioskManager.isClassicPhotosEnabled();
    if (!mounted || classicEnabled || _redirectingToAi) return;
    _redirectingToAi = true;
    await _chooseAi();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  Future<void> _chooseAi() async {
    if (!mounted) return;
    final prefill = widget.capturePrefillPhoto;
    await pushReplacementKioskFade<void, void>(
      context,
      PhotoCaptureScreen(
        key: ValueKey<Object?>(prefill),
      ),
      settings: RouteSettings(
        name: AppConstants.kRouteCapture,
        arguments: prefill == null ? null : <String, Object?>{'photo': prefill},
      ),
    );
  }

  Future<void> _chooseFotoFlash() async {
    final theme = await _viewModel.prepareFotoFlashback();
    if (!mounted) return;
    if (theme == null) {
      AppSnackBar.showError(
        context,
        _viewModel.errorMessage ?? AppStrings.experienceFotoFlashUnavailable,
      );
      return;
    }
    await navigateToFotoFlashbackCapture(
      context: context,
      theme: theme,
      replace: true,
      shotMode: _classicShotMode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Scaffold(
        backgroundColor: appColors.backgroundColor,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Atmosphere only — dimmed so templates don’t compete with the choice.
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
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 28,
                  ),
                  child: CenteredMaxWidth(
                    maxWidth: 640,
                    child: Consumer<ExperienceChoiceViewModel>(
                      builder: (context, vm, _) {
                        return _ExperienceChoicePanel(
                          appColors: appColors,
                          isLoading: vm.isLoading,
                          fotoFlashAvailable: vm.fotoFlashAvailable,
                          startingFlashback: vm.isStartingFlashback,
                          classicShotMode: _classicShotMode,
                          onClassicShotModeChanged: (mode) {
                            if (mode == null) return;
                            setState(() => _classicShotMode = mode);
                          },
                          onAi: () => unawaited(_chooseAi()),
                          onFotoFlash: () => unawaited(_chooseFotoFlash()),
                          onBackToTerms: () {
                            Navigator.of(context).pushReplacementNamed(
                              AppConstants.kRouteTerms,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExperienceChoicePanel extends StatelessWidget {
  const _ExperienceChoicePanel({
    required this.appColors,
    required this.isLoading,
    required this.fotoFlashAvailable,
    required this.startingFlashback,
    required this.classicShotMode,
    required this.onClassicShotModeChanged,
    required this.onAi,
    required this.onFotoFlash,
    required this.onBackToTerms,
  });

  final AppColors appColors;
  final bool isLoading;
  final bool fotoFlashAvailable;
  final bool startingFlashback;
  final ClassicShotMode classicShotMode;
  final ValueChanged<ClassicShotMode?> onClassicShotModeChanged;
  final VoidCallback onAi;
  final VoidCallback onFotoFlash;
  final VoidCallback onBackToTerms;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 20),
      decoration: BoxDecoration(
        color: appColors.cardBackgroundColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.experienceChoiceTitle,
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
            AppStrings.experienceChoiceSubtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: appColors.secondaryTextColor,
              fontSize: 15,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 28),
          if (isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: CircularProgressIndicator(color: appColors.primaryColor),
              ),
            )
          else ...[
            _ExperienceOptionCard(
              title: AppStrings.experienceAiTitle,
              subtitle: AppStrings.experienceAiSubtitle,
              preview: const ExperienceFotoZenThumb(),
              accent: const Color(0xFF6B4EFF),
              onTap: onAi,
            ),
            const SizedBox(height: 14),
            _ExperienceOptionCard(
              title: AppStrings.experienceFotoFlashTitle,
              subtitle: fotoFlashAvailable
                  ? AppStrings.experienceFotoFlashSubtitle
                  : AppStrings.experienceFotoFlashUnavailable,
              preview: ExperienceClassicThumb(
                accent: const Color(0xFFD4922A),
                muted: !fotoFlashAvailable,
                busy: startingFlashback,
              ),
              accent: const Color(0xFFD4922A),
              enabled: fotoFlashAvailable && !startingFlashback,
              busy: startingFlashback,
              onTap: onFotoFlash,
              footer: fotoFlashAvailable
                  ? _ClassicShotModeDropdown(
                      value: classicShotMode,
                      enabled: !startingFlashback,
                      onChanged: onClassicShotModeChanged,
                    )
                  : null,
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: onBackToTerms,
            child: Text(
              AppStrings.experienceBackToTerms,
              style: TextStyle(
                color: appColors.secondaryTextColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact shot-count control — default stays 4-shot until opened.
class _ClassicShotModeDropdown extends StatelessWidget {
  const _ClassicShotModeDropdown({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final ClassicShotMode value;
  final bool enabled;
  final ValueChanged<ClassicShotMode?> onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Text(
            AppStrings.experienceClassicShotModeLabel,
            style: TextStyle(
              color: appColors.secondaryTextColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: appColors.backgroundColor.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: appColors.borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ClassicShotMode>(
                    value: value,
                    isExpanded: true,
                    isDense: true,
                    borderRadius: BorderRadius.circular(12),
                    dropdownColor: appColors.cardBackgroundColor,
                    style: TextStyle(
                      color: appColors.textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    iconEnabledColor: const Color(0xFFD4922A),
                    items: const [
                      DropdownMenuItem(
                        value: ClassicShotMode.fourShot,
                        child: Text(AppStrings.experienceClassicFourShot),
                      ),
                      DropdownMenuItem(
                        value: ClassicShotMode.single6x4,
                        child: Text(AppStrings.experienceClassicOneShot),
                      ),
                    ],
                    onChanged: enabled ? onChanged : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExperienceOptionCard extends StatelessWidget {
  const _ExperienceOptionCard({
    required this.title,
    required this.subtitle,
    required this.preview,
    required this.accent,
    required this.onTap,
    this.enabled = true,
    this.busy = false,
    this.footer,
  });

  final String title;
  final String subtitle;
  final Widget preview;
  final Color accent;
  final VoidCallback onTap;
  final bool enabled;
  final bool busy;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final muted = !enabled;
    final titleColor =
        muted ? appColors.secondaryTextColor : appColors.textColor;
    final subtitleColor = muted
        ? appColors.secondaryTextColor.withValues(alpha: 0.7)
        : appColors.secondaryTextColor;

    return Material(
      color: muted
          ? appColors.backgroundColor.withValues(alpha: 0.55)
          : accent.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: enabled && !busy ? onTap : null,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: muted ? appColors.borderColor : accent,
              width: muted ? 1 : 2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  preview,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: 14,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (busy) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: accent,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 18,
                    color: muted ? appColors.secondaryTextColor : accent,
                  ),
                ],
              ),
              if (footer != null)
                GestureDetector(
                  onTap: () {}, // Keep dropdown taps from starting Classic.
                  behavior: HitTestBehavior.opaque,
                  child: footer!,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
