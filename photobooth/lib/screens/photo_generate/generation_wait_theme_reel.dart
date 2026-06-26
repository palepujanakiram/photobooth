import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/theme_manager.dart';
import '../../views/widgets/cached_network_image.dart';
import '../theme_selection/theme_model.dart';
import '../theme_selection/theme_preview_screen.dart';
import '../../utils/app_strings.dart';

/// Thin horizontal auto-scroll strip of other theme samples for passersby.
class GenerationWaitThemePreviewReel extends StatefulWidget {
  const GenerationWaitThemePreviewReel({
    super.key,
    this.excludeThemeId,
  });

  final String? excludeThemeId;

  @override
  State<GenerationWaitThemePreviewReel> createState() =>
      _GenerationWaitThemePreviewReelState();
}

class _GenerationWaitThemePreviewReelState
    extends State<GenerationWaitThemePreviewReel> {
  final ScrollController _scroll = ScrollController();
  Timer? _autoScrollTimer;

  @override
  void initState() {
    super.initState();
    unawaited(ThemeManager().fetchThemes());
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 48), (_) {
      if (!_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      if (max <= 0) return;
      var next = _scroll.offset + 0.8;
      if (next >= max) next = 0;
      _scroll.jumpTo(next);
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  List<ThemeModel> _themes() {
    final exclude = widget.excludeThemeId?.trim() ?? '';
    final themes = ThemeManager().getActiveThemes();
    final out = <ThemeModel>[];
    for (final t in themes) {
      if (t.id == exclude) continue;
      final url = ThemePreviewScreen.resolveSampleImageUrl(t);
      if (url.trim().isEmpty) continue;
      out.add(t);
      if (out.length >= 14) break;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final themes = _themes();
    if (themes.isEmpty) return const SizedBox.shrink();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStrings.generationWaitThemeReelTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 76,
            child: ListView.separated(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: themes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final theme = themes[index];
                final url = ThemePreviewScreen.resolveSampleImageUrl(theme);
                return _ReelCard(themeName: theme.name, imageUrl: url);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReelCard extends StatelessWidget {
  const _ReelCard({required this.themeName, required this.imageUrl});

  final String themeName;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      child: Column(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  width: 64,
                  filterQuality: FilterQuality.low,
                  placeholder: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  errorWidget: ColoredBox(
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            themeName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.65),
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
