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
                      const SizedBox(height: 12),
                      Expanded(
                        child: viewModel.isPreparingPreview
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(
                                      color: Colors.amber,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      AppStrings.flashbackPreparingPreview,
                                      style: TextStyle(
                                        color: Colors.amber.shade100,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : _LookPickerBody(
                                imageDataUrls: viewModel.imageDataUrls,
                                filterId: viewModel.selectedFilterId,
                                filters: viewModel.filters,
                                isLoading: viewModel.isLoading,
                                onSelectFilter: viewModel.selectFilter,
                              ),
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
                              : viewModel.isPreparingPreview
                                  ? AppStrings.flashbackPreparingPreview
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
    required this.filterId,
    required this.filters,
    required this.isLoading,
    required this.onSelectFilter,
  });

  final List<String> imageDataUrls;
  final String filterId;
  final List<StripFilter> filters;
  final bool isLoading;
  final ValueChanged<String> onSelectFilter;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelH = constraints.maxHeight;
        if (panelH <= 0) return const SizedBox.shrink();

        final stripH = panelH;
        final stripW = stripH * FotoFlashbackStripPreview.aspectRatio;

        return SizedBox(
          height: panelH,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FotoFlashbackStripPreview(
                imageDataUrls: imageDataUrls,
                filterId: filterId,
                width: stripW,
                height: stripH,
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
