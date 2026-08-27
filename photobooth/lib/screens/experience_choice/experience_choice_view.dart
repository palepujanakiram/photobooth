import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/kiosk_manager.dart';
import '../../services/session_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/capture_session_kind.dart';
import '../../utils/classic_shot_choice_options.dart';
import '../../utils/classic_shot_mode.dart';
import '../../utils/classic_capture_intent.dart';
import '../../utils/constants.dart';
import '../../utils/fotoflashback_navigation.dart';
import '../../utils/kiosk_offline_ux.dart';
import '../../utils/kiosk_page_route.dart';
import '../../utils/logger.dart';
import '../../utils/route_args.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/animated_slideshow_background.dart';
import '../../views/widgets/centered_max_width.dart';
import '../classic_shot_choice/classic_shot_choice_view.dart';
import '../photo_capture/capture_screen_factory.dart';
import 'experience_choice_view_widgets.dart';
import 'experience_choice_viewmodel.dart';

/// After terms: guest picks FotoZen AI vs Classic.
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
  /// null while loading kiosk Classic flag from prefs / bind cache.
  bool? _classicEnabled;
  List<int> _classicShotModes = const [1, 3, 4];

  @override
  void initState() {
    super.initState();
    _kioskManager = widget.kioskManager ?? KioskManager();
    _viewModel = ExperienceChoiceViewModel();
    unawaited(_viewModel.load());
    unawaited(_resolveClassicGate());
  }

  /// Defensive: if Classic is off, skip this screen online (deep link / stale).
  /// Offline: never auto-enter AI — show a clear message instead.
  Future<void> _resolveClassicGate() async {
    final classicEnabled = await _kioskManager.isClassicPhotosEnabled();
    final modes = await _kioskManager.getClassicShotModes();
    if (!mounted) return;
    setState(() {
      _classicEnabled = classicEnabled;
      _classicShotModes = modes;
    });
    if (classicEnabled || _redirectingToAi) return;
    if (KioskOfflineUx.shouldDisableAiExperience(
      sessionOffline: SessionManager().isOfflineSession,
    )) {
      return;
    }
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
    if (KioskOfflineUx.shouldDisableAiExperience(
      sessionOffline: SessionManager().isOfflineSession,
    )) {
      AppSnackBar.showError(
        context,
        AppStrings.experienceOfflineAiBlockedSnack,
      );
      return;
    }
    // Do not let a stale Classic intent lock AI POSE into strip mode.
    ClassicCaptureIntent.clear();
    final prefill = widget.capturePrefillPhoto;
    await pushReplacementKioskFade<void, void>(
      context,
      buildCaptureScreen(
        key: ValueKey<Object?>('ai-pose-${prefill ?? 'fresh'}'),
        sessionKind: CaptureSessionKind.fotoZen,
        context: context,
      ),
      settings: RouteSettings(
        // Distinct name so Android TV cannot reuse Classic `/capture` args.
        name: '${AppConstants.kRouteCapture}-ai',
        arguments: prefill == null ? null : <String, Object?>{'photo': prefill},
      ),
    );
  }

  /// Classic card / single-mode CTA. When multiple modes are enabled, opens
  /// the preview screen; otherwise starts capture for the only mode.
  Future<void> _chooseFotoFlash([ClassicShotMode? shotMode]) async {
    final theme = await _viewModel.prepareFotoFlashback();
    if (!mounted) return;
    if (theme == null) {
      AppSnackBar.showError(
        context,
        _viewModel.errorMessage ?? AppStrings.experienceFotoFlashUnavailable,
      );
      return;
    }

    if (classicShotChoiceUsesPreviewScreen(_classicShotModes)) {
      AppLogger.debug(
        'Classic → shot choice: modes=$_classicShotModes',
      );
      await pushReplacementKioskFade<void, void>(
        context,
        ClassicShotChoiceScreen(
          theme: theme,
          modes: _classicShotModes,
        ),
        settings: RouteSettings(
          name: AppConstants.kRouteClassicShotChoice,
          arguments: ClassicShotChoiceArgs(
            theme: theme,
            modes: _classicShotModes,
          ),
        ),
      );
      return;
    }

    final mode = shotMode ??
        classicShotModeForCount(_classicShotModes.first) ??
        ClassicShotMode.fourShot;
    AppLogger.debug(
      'Classic start: shotMode=$mode shotCount=${mode.shotCount}',
    );
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
                        final classicOn = _classicEnabled ?? true;
                        final classicReady =
                            classicOn && vm.fotoFlashAvailable;
                        return _ExperienceChoicePanel(
                          appColors: appColors,
                          isLoading: vm.isLoading,
                          offline: vm.isOffline,
                          aiAvailable: vm.aiAvailable,
                          fotoFlashAvailable: classicReady,
                          startingFlashback: vm.isStartingFlashback,
                          classicShotModes: _classicShotModes,
                          onAi: () => unawaited(_chooseAi()),
                          onFotoFlash: () => unawaited(_chooseFotoFlash()),
                          onFotoFlashMode: (mode) =>
                              unawaited(_chooseFotoFlash(mode)),
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
    required this.offline,
    required this.aiAvailable,
    required this.fotoFlashAvailable,
    required this.startingFlashback,
    required this.classicShotModes,
    required this.onAi,
    required this.onFotoFlash,
    required this.onFotoFlashMode,
    required this.onBackToTerms,
  });

  final AppColors appColors;
  final bool isLoading;
  final bool offline;
  final bool aiAvailable;
  final bool fotoFlashAvailable;
  final bool startingFlashback;
  final List<int> classicShotModes;
  final VoidCallback onAi;
  final VoidCallback onFotoFlash;
  final void Function(ClassicShotMode mode) onFotoFlashMode;
  final VoidCallback onBackToTerms;

  @override
  Widget build(BuildContext context) {
    final noPath = offline && !fotoFlashAvailable && !isLoading;
    final multiClassic = classicShotChoiceUsesPreviewScreen(classicShotModes);
    final classicSubtitle = _classicCardSubtitle(
      available: fotoFlashAvailable,
      multiMode: multiClassic,
    );
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
            noPath
                ? AppStrings.experienceOfflineNoClassicMessage
                : offline
                    ? AppStrings.experienceOfflineBanner
                    : AppStrings.experienceChoiceSubtitle,
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
          else if (!noPath) ...[
            _ExperienceOptionCard(
              title: AppStrings.experienceAiTitle,
              subtitle: aiAvailable
                  ? AppStrings.experienceAiSubtitle
                  : AppStrings.experienceAiOfflineSubtitle,
              preview: ExperienceFotoZenThumb(muted: !aiAvailable),
              accent: const Color(0xFF6B4EFF),
              enabled: aiAvailable,
              onTap: aiAvailable ? onAi : null,
            ),
            const SizedBox(height: 14),
            _ExperienceOptionCard(
              title: AppStrings.experienceFotoFlashTitle,
              subtitle: classicSubtitle,
              preview: ExperienceClassicThumb(
                accent: const Color(0xFFD4922A),
                muted: !fotoFlashAvailable || startingFlashback,
              ),
              accent: const Color(0xFFD4922A),
              enabled: fotoFlashAvailable && !startingFlashback,
              busy: startingFlashback,
              onTap: fotoFlashAvailable && !startingFlashback && multiClassic
                  ? onFotoFlash
                  : null,
              footer: fotoFlashAvailable && !multiClassic
                  ? _ClassicShotStartButtons(
                      enabled: !startingFlashback,
                      modes: classicShotModes,
                      onStart: onFotoFlashMode,
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

  static String _classicCardSubtitle({
    required bool available,
    required bool multiMode,
  }) {
    if (!available) return AppStrings.experienceFotoFlashUnavailable;
    if (multiMode) return AppStrings.experienceFotoFlashSubtitle;
    return AppStrings.experienceFotoFlashSubtitleSingle;
  }
}

/// Explicit Classic CTAs when only one shot mode is enabled on the kiosk.
class _ClassicShotStartButtons extends StatelessWidget {
  const _ClassicShotStartButtons({
    required this.enabled,
    required this.modes,
    required this.onStart,
  });

  final bool enabled;
  final List<int> modes;
  final void Function(ClassicShotMode mode) onStart;

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final entries = <({ClassicShotMode mode, String label, bool primary})>[];
    if (modes.contains(1)) {
      entries.add((
        mode: ClassicShotMode.single6x4,
        label: AppStrings.experienceClassicStartOneShot,
        primary: false,
      ));
    }
    if (modes.contains(3)) {
      entries.add((
        mode: ClassicShotMode.threeShot,
        label: AppStrings.experienceClassicStartThreeShot,
        primary: modes.length == 1 || !modes.contains(4),
      ));
    }
    if (modes.contains(4)) {
      entries.add((
        mode: ClassicShotMode.fourShot,
        label: AppStrings.experienceClassicStartFourShot,
        primary: true,
      ));
    }
    if (entries.isEmpty) return const SizedBox.shrink();

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
          ...[
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _shotButton(
                appColors: appColors,
                enabled: enabled,
                label: entries[i].label,
                primary: entries[i].primary,
                onPressed: () => onStart(entries[i].mode),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _shotButton({
    required AppColors appColors,
    required bool enabled,
    required String label,
    required bool primary,
    required VoidCallback onPressed,
  }) {
    if (primary) {
      return FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFD4922A),
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size.fromHeight(52),
        ),
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: enabled ? onPressed : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: appColors.textColor,
        side: BorderSide(color: appColors.borderColor),
        padding: const EdgeInsets.symmetric(vertical: 16),
        minimumSize: const Size.fromHeight(52),
      ),
      child: Text(label),
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
