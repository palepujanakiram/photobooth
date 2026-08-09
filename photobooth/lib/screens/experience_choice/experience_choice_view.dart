import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/kiosk_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/capture_session_kind.dart';
import '../../utils/classic_shot_mode.dart';
import '../../utils/classic_capture_intent.dart';
import '../../utils/constants.dart';
import '../../utils/fotoflashback_navigation.dart';
import '../../utils/kiosk_page_route.dart';
import '../../utils/logger.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/animated_slideshow_background.dart';
import '../../views/widgets/centered_max_width.dart';
import '../photo_capture/photo_capture_view.dart';
import 'experience_choice_view_widgets.dart';
import 'experience_choice_viewmodel.dart';

/// After terms: guest picks FotoZen AI vs Classic (1-shot or 4-shot).
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
    // Do not let a stale Classic intent lock AI POSE into strip mode.
    ClassicCaptureIntent.clear();
    final prefill = widget.capturePrefillPhoto;
    await pushReplacementKioskFade<void, void>(
      context,
      PhotoCaptureScreen(
        key: ValueKey<Object?>('ai-pose-${prefill ?? 'fresh'}'),
        sessionKind: CaptureSessionKind.fotoZen,
      ),
      settings: RouteSettings(
        // Distinct name so Android TV cannot reuse Classic `/capture` args.
        name: '${AppConstants.kRouteCapture}-ai',
        arguments: prefill == null ? null : <String, Object?>{'photo': prefill},
      ),
    );
  }

  /// [shotMode] comes from the tapped CTA — never a separate selector that can
  /// desync from the Classic card tap (that was sending guests into 4-shot).
  Future<void> _chooseFotoFlash(ClassicShotMode shotMode) async {
    final theme = await _viewModel.prepareFotoFlashback();
    if (!mounted) return;
    if (theme == null) {
      AppSnackBar.showError(
        context,
        _viewModel.errorMessage ?? AppStrings.experienceFotoFlashUnavailable,
      );
      return;
    }
    AppLogger.debug(
      'Classic start: shotMode=$shotMode shotCount=${shotMode.shotCount}',
    );
    await navigateToFotoFlashbackCapture(
      context: context,
      theme: theme,
      replace: true,
      shotMode: shotMode,
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
                          onAi: () => unawaited(_chooseAi()),
                          onFotoFlashOneShot: () => unawaited(
                            _chooseFotoFlash(ClassicShotMode.single6x4),
                          ),
                          onFotoFlashFourShot: () => unawaited(
                            _chooseFotoFlash(ClassicShotMode.fourShot),
                          ),
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
    required this.onAi,
    required this.onFotoFlashOneShot,
    required this.onFotoFlashFourShot,
    required this.onBackToTerms,
  });

  final AppColors appColors;
  final bool isLoading;
  final bool fotoFlashAvailable;
  final bool startingFlashback;
  final VoidCallback onAi;
  final VoidCallback onFotoFlashOneShot;
  final VoidCallback onFotoFlashFourShot;
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
                muted: !fotoFlashAvailable || startingFlashback,
              ),
              accent: const Color(0xFFD4922A),
              enabled: fotoFlashAvailable && !startingFlashback,
              // Single spinner next to the title (not also on the strip thumb).
              busy: startingFlashback,
              footer: fotoFlashAvailable
                  ? _ClassicShotStartButtons(
                      enabled: !startingFlashback,
                      onOneShot: onFotoFlashOneShot,
                      onFourShot: onFotoFlashFourShot,
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

/// Two explicit Classic CTAs so 1-shot cannot accidentally launch as 4-shot.
class _ClassicShotStartButtons extends StatelessWidget {
  const _ClassicShotStartButtons({
    required this.enabled,
    required this.onOneShot,
    required this.onFourShot,
  });

  final bool enabled;
  final VoidCallback onOneShot;
  final VoidCallback onFourShot;

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.experienceClassicShotModeLabel,
            style: TextStyle(
              color: appColors.secondaryTextColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: enabled ? onOneShot : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: appColors.textColor,
                    side: BorderSide(color: appColors.borderColor),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text(AppStrings.experienceClassicStartOneShot),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: enabled ? onFourShot : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD4922A),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text(AppStrings.experienceClassicStartFourShot),
                ),
              ),
            ],
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
    this.onTap,
    this.enabled = true,
    this.busy = false,
    this.footer,
  });

  final String title;
  final String subtitle;
  final Widget preview;
  final Color accent;
  final VoidCallback? onTap;
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

    final header = Row(
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
        if (onTap != null)
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 18,
            color: muted ? appColors.secondaryTextColor : accent,
          ),
      ],
    );

    return Material(
      color: muted
          ? appColors.backgroundColor.withValues(alpha: 0.55)
          : accent.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(16),
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
            if (onTap != null)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: enabled && !busy ? onTap : null,
                child: header,
              )
            else
              header,
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }
}
