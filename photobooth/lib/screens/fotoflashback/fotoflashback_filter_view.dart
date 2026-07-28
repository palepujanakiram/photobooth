import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/strip_models.dart';
import '../../services/app_settings_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/fotoflashback_payment_helpers.dart';
import '../../utils/payment_workflow_helpers.dart';
import '../../utils/route_args.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/centered_max_width.dart';
import 'fotoflashback_filter_preview.dart';
import 'fotoflashback_filter_viewmodel.dart';

/// Pick a FotoFlashback look, then pay (if configured) or compose → Result.
class FotoFlashbackFilterScreen extends StatefulWidget {
  const FotoFlashbackFilterScreen({super.key});

  @override
  State<FotoFlashbackFilterScreen> createState() =>
      _FotoFlashbackFilterScreenState();
}

class _FotoFlashbackFilterScreenState extends State<FotoFlashbackFilterScreen> {
  FotoFlashbackFilterViewModel? _viewModel;
  bool _busy = false;
  String? _ctaLabel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel != null) return;
    final args = FlashbackFilterArgs.tryParse(
      ModalRoute.of(context)?.settings.arguments,
    );
    if (args == null) return;
    _viewModel = FotoFlashbackFilterViewModel(
      theme: args.theme,
      imageDataUrls: args.imageDataUrls,
    );
    unawaited(_viewModel!.loadFilters());
    unawaited(_loadCta());
  }

  Future<void> _loadCta() async {
    final enabled = await resolvePaymentsEnabled();
    if (!mounted) return;
    final timing =
        context.read<AppSettingsManager>().settings?.paymentCollectionTiming;
    setState(() {
      _ctaLabel = flashbackContinueCta(
        paymentsEnabled: enabled,
        paymentCollectionTiming: timing,
      );
    });
  }

  Future<void> _confirmLook() async {
    final vm = _viewModel;
    if (vm == null || _busy) return;
    setState(() => _busy = true);
    try {
      final timing =
          context.read<AppSettingsManager>().settings?.paymentCollectionTiming;
      final error = await continueAfterFlashbackLook(
        context: context,
        viewModel: vm,
        paymentCollectionTiming: timing,
      );
      if (!mounted) return;
      if (error != null) {
        AppSnackBar.showError(context, error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = _viewModel;
    final appColors = AppColors.of(context);
    if (vm == null) {
      return Scaffold(
        backgroundColor: appColors.backgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final cta = _ctaLabel ?? AppStrings.flashbackComposeCta;

    return ChangeNotifierProvider.value(
      value: vm,
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1410),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: const Text(
            AppStrings.flashbackFilterTitle,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: Consumer<FotoFlashbackFilterViewModel>(
            builder: (context, viewModel, _) {
              return CenteredMaxWidth(
                maxWidth: 760,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                  child: Column(
                    children: [
                      Text(
                        AppStrings.flashbackFilterSubtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.amber.shade100.withValues(alpha: 0.8),
                          letterSpacing: 0.3,
                          fontSize: 13,
                        ),
                      ),
                      if (viewModel.isPreparingPreview) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.amber.shade300,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              AppStrings.flashbackPreparingPreview,
                              style: TextStyle(
                                color: Colors.amber.shade100
                                    .withValues(alpha: 0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      Expanded(
                        child: _LookPickerBody(
                          imageDataUrls: viewModel.previewImageDataUrls,
                          imagesAreGraded: viewModel.previewImagesAreGraded,
                          layout: viewModel.wysiwygLayout,
                          filterId: viewModel.selectedFilterId,
                          frameId: viewModel.selectedFrameId,
                          frameOverlayUrl: viewModel.selectedFrame?.overlayUrl,
                          frameCaption: viewModel.selectedFrame?.caption,
                          stickerId: viewModel.selectedStickerId,
                          placements: viewModel.stickerPlacements,
                          scribbles: viewModel.scribbles,
                          drawMode: viewModel.drawMode,
                          filters: viewModel.filters,
                          isLoading: viewModel.isLoading,
                          onSelectFilter: viewModel.selectFilter,
                          onMovePlacement: viewModel.moveSticker,
                          onRemovePlacement: viewModel.removeSticker,
                          onScribbleStart: viewModel.beginScribble,
                          onScribbleUpdate: viewModel.extendScribble,
                          onScribbleEnd: viewModel.endScribble,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _ChipPickerRow(
                        label: AppStrings.flashbackFrameLabel,
                        options: viewModel.frames
                            .map((f) => (id: f.id, name: f.name))
                            .toList(),
                        selectedId: viewModel.selectedFrameId,
                        onSelect: viewModel.selectFrame,
                      ),
                      const SizedBox(height: 6),
                      _ChipPickerRow(
                        label: AppStrings.flashbackStickerLabel,
                        options: viewModel.stickers
                            .map((s) => (id: s.id, name: s.name))
                            .toList(),
                        selectedId: viewModel.selectedStickerId,
                        onSelect: (id) {
                          if (viewModel.drawMode) {
                            viewModel.setDrawMode(false);
                          }
                          viewModel.selectSticker(id);
                        },
                      ),
                      const SizedBox(height: 6),
                      _ScribbleToolbar(
                        drawMode: viewModel.drawMode,
                        penColor: viewModel.penColor,
                        canUndo: viewModel.canUndoScribble,
                        onToggleDraw: () =>
                            viewModel.setDrawMode(!viewModel.drawMode),
                        onSelectColor: viewModel.setPenColor,
                        onUndo: viewModel.undoScribble,
                        onClear: viewModel.clearScribbles,
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade700,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(double.infinity, 56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: (viewModel.canCompose && !_busy)
                            ? () => unawaited(_confirmLook())
                            : null,
                        child: Text(
                          (viewModel.isComposing || _busy)
                              ? AppStrings.flashbackComposing
                              : cta,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Strip (left) + looks (right), top-aligned and height-matched.
class _LookPickerBody extends StatelessWidget {
  const _LookPickerBody({
    required this.imageDataUrls,
    required this.imagesAreGraded,
    required this.layout,
    required this.filterId,
    required this.frameId,
    this.frameOverlayUrl,
    this.frameCaption,
    required this.stickerId,
    required this.placements,
    required this.scribbles,
    required this.drawMode,
    required this.filters,
    required this.isLoading,
    required this.onSelectFilter,
    required this.onMovePlacement,
    required this.onRemovePlacement,
    required this.onScribbleStart,
    required this.onScribbleUpdate,
    required this.onScribbleEnd,
  });

  final List<String> imageDataUrls;
  final bool imagesAreGraded;
  final StripWysiwygLayout layout;
  final String filterId;
  final String frameId;
  final String? frameOverlayUrl;
  final String? frameCaption;
  final String stickerId;
  final List<StripStickerPlacement> placements;
  final List<StripScribbleStroke> scribbles;
  final bool drawMode;
  final List<StripFilter> filters;
  final bool isLoading;
  final ValueChanged<String> onSelectFilter;
  final void Function(String id, double x, double y) onMovePlacement;
  final ValueChanged<String> onRemovePlacement;
  final void Function(double x, double y) onScribbleStart;
  final void Function(double x, double y) onScribbleUpdate;
  final VoidCallback onScribbleEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelH = constraints.maxHeight;
        if (panelH <= 0) return const SizedBox.shrink();

        // Dual-strip chrome → tall 2×6; sheet → portrait 4×6; 1-shot → landscape 6×4.
        final single = imageDataUrls.length == 1;
        final sheet = !single && isStripSheetLayout(frameId);
        final aspect = single
            ? FotoFlashbackStripPreview.single6x4AspectRatio
            : sheet
                ? FotoFlashbackStripPreview.sheetAspectRatio
                : FotoFlashbackStripPreview.stripAspectRatio;
        var previewH = panelH;
        var previewW = previewH * aspect;
        final maxW = constraints.maxWidth * (single ? 0.58 : 0.48);
        if (previewW > maxW) {
          previewW = maxW;
          previewH = previewW / aspect;
        }

        return SizedBox(
          height: panelH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              FotoFlashbackStripPreview(
                imageDataUrls: imageDataUrls,
                imagesAreGraded: imagesAreGraded,
                layout: layout,
                filterId: filterId,
                frameId: frameId,
                frameOverlayUrl: frameOverlayUrl,
                frameCaption: frameCaption,
                stickerId: stickerId,
                placements: placements,
                scribbles: scribbles,
                drawMode: drawMode,
                onMovePlacement: onMovePlacement,
                onRemovePlacement: onRemovePlacement,
                onScribbleStart: onScribbleStart,
                onScribbleUpdate: onScribbleUpdate,
                onScribbleEnd: onScribbleEnd,
                width: previewW,
                height: previewH,
              ),
              const SizedBox(width: 20),
              Expanded(
                child: isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.amber),
                      )
                    : _FilterOptionList(
                        filters: filters,
                        selectedId: filterId,
                        onSelect: onSelectFilter,
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Compact look tiles — always fills height with no scroll (9 fits on kiosk).
class _FilterOptionList extends StatelessWidget {
  const _FilterOptionList({
    required this.filters,
    required this.selectedId,
    required this.onSelect,
  });

  final List<StripFilter> filters;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (filters.isEmpty) {
      return const SizedBox.shrink();
    }

    const gap = 6.0;
    return Column(
      children: [
        for (var i = 0; i < filters.length; i++) ...[
          if (i > 0) const SizedBox(height: gap),
          Expanded(
            child: _FilterTile(
              filter: filters[i],
              selected: filters[i].id == selectedId,
              onTap: () => onSelect(filters[i].id),
            ),
          ),
        ],
      ],
    );
  }
}

class _FilterTile extends StatelessWidget {
  const _FilterTile({
    required this.filter,
    required this.selected,
    required this.onTap,
  });

  final StripFilter filter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.amber.shade800 : Colors.white10,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  filter.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  filter.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.black87 : Colors.white70,
                    fontSize: 11,
                    height: 1.15,
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

class _ChipPickerRow extends StatelessWidget {
  const _ChipPickerRow({
    required this.label,
    required this.options,
    required this.selectedId,
    required this.onSelect,
  });

  final String label;
  final List<({String id, String name})> options;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.amber.shade100.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final opt in options) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _FlashbackChip(
                      label: opt.name,
                      selected: opt.id == selectedId,
                      onTap: () => onSelect(opt.id),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ScribbleToolbar extends StatelessWidget {
  const _ScribbleToolbar({
    required this.drawMode,
    required this.penColor,
    required this.canUndo,
    required this.onToggleDraw,
    required this.onSelectColor,
    required this.onUndo,
    required this.onClear,
  });

  final bool drawMode;
  final String penColor;
  final bool canUndo;
  final VoidCallback onToggleDraw;
  final ValueChanged<String> onSelectColor;
  final VoidCallback onUndo;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            AppStrings.flashbackScribbleLabel,
            style: TextStyle(
              color: Colors.amber.shade100.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FlashbackChip(
                  label: drawMode
                      ? AppStrings.flashbackScribbleOn
                      : AppStrings.flashbackScribbleOff,
                  selected: drawMode,
                  onTap: onToggleDraw,
                ),
                const SizedBox(width: 8),
                for (final color in kStripScribblePenColors) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () {
                        if (!drawMode) onToggleDraw();
                        onSelectColor(color);
                      },
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: _hexColor(color),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: penColor == color
                                ? Colors.amber.shade300
                                : Colors.white38,
                            width: penColor == color ? 2.2 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                TextButton(
                  onPressed: canUndo ? onUndo : null,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.amber.shade100,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text(
                    AppStrings.flashbackScribbleUndo,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: canUndo ? onClear : null,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.amber.shade100,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text(
                    AppStrings.flashbackScribbleClear,
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Frame / sticker / scribble chips — opaque colors so M3 ChoiceChip theme
/// cannot force white-on-white on this dark screen.
class _FlashbackChip extends StatelessWidget {
  const _FlashbackChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const Color _unselectedFill = Color(0xFF3A322C);
  static const Color _unselectedBorder = Color(0x66FFFFFF);

  @override
  Widget build(BuildContext context) {
    final fill = selected ? Colors.amber.shade700 : _unselectedFill;
    final border =
        selected ? Colors.amber.shade400 : _unselectedBorder;
    final foreground = selected ? Colors.black : Colors.white;
    return Material(
      color: fill,
      shape: StadiumBorder(side: BorderSide(color: border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check, size: 14, color: foreground),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _hexColor(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  return Color(int.parse('FF$cleaned', radix: 16));
}
