import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/app_strings.dart';
import 'generation_wait_helpers.dart';
import 'generation_wait_story_helpers.dart';
import 'photo_generate_viewmodel.dart';

/// Story-driven header: act headline, dynamic quote, theme chip, reward checklist.
class GenerationWaitStoryHeader extends StatelessWidget {
  const GenerationWaitStoryHeader({
    super.key,
    required this.viewModel,
    required this.presentation,
    this.compact = false,
    this.hideRewardWhenPolishing = false,
  });

  final PhotoGenerateViewModel viewModel;
  final GenerationWaitPresentation presentation;

  /// When true, only compact chrome (chip + reward row) — headline lives in app bar.
  final bool compact;

  /// Hides reward pills when the polish strip is shown in the footer.
  final bool hideRewardWhenPolishing;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return GenerationWaitStoryChrome(
        viewModel: viewModel,
        presentation: presentation,
        hideRewardWhenPolishing: hideRewardWhenPolishing,
      );
    }
    final themeName = viewModel.selectedTheme?.name.trim();
    final actHeadline = generationWaitActHeadline(viewModel, presentation);
    final quote = generationWaitDynamicQuote(viewModel.elapsedSeconds);
    final beats = resolveGenerationWaitRewardChecklist(viewModel, presentation);
    final showFaceScan = generationWaitShowFaceScanChecklist(viewModel, presentation);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        children: [
          Text(
            actHeadline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 22,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            quote,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
          if (themeName != null && themeName.isNotEmpty) ...[
            const SizedBox(height: 12),
            GenerationWaitThemeChip(themeName: themeName),
          ],
          if (showFaceScan) ...[
            const SizedBox(height: 14),
            GenerationWaitFaceScanChecklist(
              completedCount: generationWaitFaceScanCompletedCount(
                viewModel.elapsedSeconds,
              ),
            ),
          ],
          const SizedBox(height: 14),
          GenerationWaitRewardChecklist(beats: beats),
        ],
      ),
    );
  }
}

/// Compact body chrome: theme chip + horizontal reward progress.
class GenerationWaitStoryChrome extends StatelessWidget {
  const GenerationWaitStoryChrome({
    super.key,
    required this.viewModel,
    required this.presentation,
    this.hideRewardWhenPolishing = false,
  });

  final PhotoGenerateViewModel viewModel;
  final GenerationWaitPresentation presentation;
  final bool hideRewardWhenPolishing;

  @override
  Widget build(BuildContext context) {
    final themeName = viewModel.selectedTheme?.name.trim();
    final beats = resolveGenerationWaitRewardChecklist(viewModel, presentation);
    final showRewards = !hideRewardWhenPolishing;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (themeName != null && themeName.isNotEmpty) ...[
          GenerationWaitThemeChip(themeName: themeName),
          if (showRewards) const SizedBox(height: 10),
        ],
        if (showRewards) GenerationWaitRewardChecklistCompact(beats: beats),
      ],
    );
  }
}

/// Horizontal reward beats for compact kiosk chrome.
class GenerationWaitRewardChecklistCompact extends StatelessWidget {
  const GenerationWaitRewardChecklistCompact({super.key, required this.beats});

  final List<GenerationWaitRewardBeat> beats;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final beat in beats) _RewardBeatChip(beat: beat),
      ],
    );
  }
}

class _RewardBeatChip extends StatelessWidget {
  const _RewardBeatChip({required this.beat});

  final GenerationWaitRewardBeat beat;

  @override
  Widget build(BuildContext context) {
    final bool done = beat.state == GenerationWaitBeatState.done;
    final bool active = beat.state == GenerationWaitBeatState.active;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: done
            ? const Color(0xFF22C55E).withValues(alpha: 0.18)
            : active
                ? CupertinoColors.activeBlue.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: done
              ? const Color(0xFF22C55E).withValues(alpha: 0.45)
              : active
                  ? CupertinoColors.activeBlue.withValues(alpha: 0.55)
                  : Colors.white12,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          beat.label,
          style: TextStyle(
            color: done || active
                ? Colors.white.withValues(alpha: 0.92)
                : Colors.white.withValues(alpha: 0.45),
            fontSize: 11,
            fontWeight: active || done ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// Face-scan lines overlaid on the center of the wait hero card.
class GenerationWaitFaceScanOverlay extends StatelessWidget {
  const GenerationWaitFaceScanOverlay({super.key, required this.completedCount});

  final int completedCount;

  @override
  Widget build(BuildContext context) {
    if (completedCount <= 0) return const SizedBox.shrink();
    final visible = kGenerationWaitFaceScanLines
        .take(completedCount.clamp(0, kGenerationWaitFaceScanLines.length));
    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final line in visible)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          size: 13,
                          color: Color(0xFF22C55E),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            line,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill showing the selected theme name above the wait hero.
class GenerationWaitThemeChip extends StatelessWidget {
  const GenerationWaitThemeChip({super.key, required this.themeName});

  final String themeName;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Text(
          themeName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// Act 1 scripted scan checklist — one line per second.
class GenerationWaitFaceScanChecklist extends StatelessWidget {
  const GenerationWaitFaceScanChecklist({super.key, required this.completedCount});

  final int completedCount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            for (var i = 0; i < kGenerationWaitFaceScanLines.length; i++)
              _FaceScanRow(
                label: kGenerationWaitFaceScanLines[i],
                done: i < completedCount,
                isNext: i == completedCount,
              ),
          ],
        ),
      ),
    );
  }
}

class _FaceScanRow extends StatelessWidget {
  const _FaceScanRow({
    required this.label,
    required this.done,
    required this.isNext,
  });

  final String label;
  final bool done;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final icon = done
        ? const Icon(Icons.check_circle, size: 16, color: Color(0xFF22C55E))
        : isNext
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: CupertinoColors.activeBlue.withValues(alpha: 0.9),
                ),
              )
            : Icon(
                Icons.circle_outlined,
                size: 16,
                color: Colors.white.withValues(alpha: 0.25),
              );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: done
                    ? Colors.white.withValues(alpha: 0.92)
                    : isNext
                        ? Colors.white.withValues(alpha: 0.85)
                        : Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
                fontWeight: done || isNext ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reward-style checklist replacing percentage progress.
class GenerationWaitRewardChecklist extends StatelessWidget {
  const GenerationWaitRewardChecklist({super.key, required this.beats});

  final List<GenerationWaitRewardBeat> beats;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            for (final beat in beats) _RewardBeatRow(beat: beat),
          ],
        ),
      ),
    );
  }
}

class _RewardBeatRow extends StatelessWidget {
  const _RewardBeatRow({required this.beat});

  final GenerationWaitRewardBeat beat;

  @override
  Widget build(BuildContext context) {
    final Widget leading;
    switch (beat.state) {
      case GenerationWaitBeatState.done:
        leading = const Icon(Icons.check, size: 16, color: Color(0xFF22C55E));
      case GenerationWaitBeatState.active:
        leading = SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: CupertinoColors.activeBlue.withValues(alpha: 0.95),
          ),
        );
      case GenerationWaitBeatState.pending:
        leading = Icon(
          Icons.circle_outlined,
          size: 16,
          color: Colors.white.withValues(alpha: 0.28),
        );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              beat.label,
              style: TextStyle(
                color: beat.state == GenerationWaitBeatState.pending
                    ? Colors.white.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: beat.state == GenerationWaitBeatState.active
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
          ),
          if (beat.state == GenerationWaitBeatState.done)
            Text(
              '✓',
              style: TextStyle(
                color: const Color(0xFF22C55E).withValues(alpha: 0.9),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact fact tip + privacy (kiosk CREATE screen).
class GenerationWaitEducationalFooter extends StatelessWidget {
  const GenerationWaitEducationalFooter({
    super.key,
    required this.elapsedSeconds,
    this.compact = false,
    this.hideFactWhenPolishing = false,
  });

  final int elapsedSeconds;
  final bool compact;
  final bool hideFactWhenPolishing;

  @override
  Widget build(BuildContext context) {
    final card = generationWaitFactCard(elapsedSeconds);

    if (compact) {
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          children: [
            if (!hideFactWhenPolishing) ...[
              Text(
                card.body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.72),
                  fontSize: 12,
                  height: 1.35,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),
            ],
            _privacyRow(),
          ],
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  Text(
                    AppStrings.generationWaitDidYouKnowTitle,
                    style: TextStyle(
                      color: CupertinoColors.activeBlue.withValues(alpha: 0.95),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    card.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    card.body,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.generationWaitTimeExpectation,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          _privacyRow(),
        ],
      ),
    );
  }

  Widget _privacyRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          CupertinoIcons.lock_fill,
          size: 12,
          color: Colors.white.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 6),
        Text(
          AppStrings.generationWaitPrivacyFooter,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// Rotating mall marketing line — peripheral, below the theme reel.
class GenerationWaitMarketingTagline extends StatelessWidget {
  const GenerationWaitMarketingTagline({super.key, required this.elapsedSeconds});

  final int elapsedSeconds;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        generationWaitMarketingTagline(elapsedSeconds),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.42),
          fontSize: 11,
          fontStyle: FontStyle.italic,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
