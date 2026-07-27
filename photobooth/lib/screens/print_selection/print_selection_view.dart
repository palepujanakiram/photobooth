import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings_manager.dart';
import '../../services/print_selection_coordinator.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/print_orientation.dart';
import '../../utils/route_args.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/cached_network_image.dart';
import '../photo_generate/photo_generate_viewmodel.dart';
import 'print_selection_viewmodel.dart';

/// Hub after Classic strip (and Explore more AI): pick what to print, then pay.
class PrintSelectionScreen extends StatefulWidget {
  const PrintSelectionScreen({super.key});

  @override
  State<PrintSelectionScreen> createState() => _PrintSelectionScreenState();
}

class _PrintSelectionScreenState extends State<PrintSelectionScreen> {
  PrintSelectionViewModel? _viewModel;
  bool _exploreLaunchScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    final args = PrintSelectionArgs.tryParse(raw);
    final coordinator = PrintSelectionCoordinator.instance;
    final images = args?.generatedImages ??
        List<GeneratedImage>.from(coordinator.images);
    _viewModel = PrintSelectionViewModel(
      images: images,
      stripPrintSize: args?.stripPrintSize ?? coordinator.stripPrintSize,
      transformationRunId:
          args?.transformationRunId ?? coordinator.transformationRunId,
      // Must use the Provider instance — a bare AppSettingsManager() has no
      // kiosk prices and falls back to ₹100 defaults.
      appSettingsManager: context.read<AppSettingsManager>(),
    );
    if (coordinator.awaitingExploreMoreReturn && !_exploreLaunchScheduled) {
      _exploreLaunchScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _startExploreMoreAi();
      });
    }
  }

  @override
  void dispose() {
    _viewModel?.dispose();
    super.dispose();
  }

  Future<void> _startExploreMoreAi() async {
    final coordinator = PrintSelectionCoordinator.instance;
    coordinator.markExploreMore();
    if (!mounted) return;
    // Do not await — capture uses pushReplacement into theme/generate.
    unawaited(Navigator.of(context).pushNamed(AppConstants.kRouteCapture));
  }

  Future<void> _continueToPay() async {
    final vm = _viewModel;
    if (vm == null) return;
    final selected = vm.selectedImages;
    if (selected.isEmpty) return;
    if (!mounted) return;
    PrintSelectionCoordinator.instance.awaitingExploreMoreReturn = false;
    final size = vm.stripPrintSize?.trim();
    final runId = vm.transformationRunId?.trim();
    await Navigator.of(context).pushNamed(
      AppConstants.kRouteResult,
      arguments: ResultArgs(
        generatedImages: selected,
        printOrientation: PrintOrientation.portrait,
        printSize: (size != null && size.isNotEmpty)
            ? size
            : AppConstants.kPrintSizeStripDual2x6,
        transformationRunId:
            (runId != null && runId.isNotEmpty) ? runId : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = _viewModel;
    if (vm == null) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final colors = AppColors.of(context);
    return ChangeNotifierProvider.value(
      value: vm,
      child: Scaffold(
        backgroundColor: colors.backgroundColor,
        body: SafeArea(
          child: Consumer<PrintSelectionViewModel>(
            builder: (context, vm, _) {
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AppStrings.printSelectionTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            color: colors.textColor,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppStrings.printSelectionSubtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: colors.secondaryTextColor,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: vm.images.length,
                        itemBuilder: (context, index) {
                          final image = vm.images[index];
                          return _PrintSelectionTile(
                            image: image,
                            isStrip: vm.isStripImage(image),
                            onTap: () => vm.toggleSelected(image.id),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppStrings.printSelectionTotal(vm.selectedTotalPrice),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: colors.textColor,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: vm.canContinue ? _continueToPay : null,
                      child: Text(
                        AppStrings.printSelectionContinue(vm.selectedCount),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PrintSelectionTile extends StatelessWidget {
  const _PrintSelectionTile({
    required this.image,
    required this.isStrip,
    required this.onTap,
  });

  final GeneratedImage image;
  final bool isStrip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final selected = image.isSelected;
    final label = isStrip
        ? AppStrings.printSelectionStripLabel
        : (image.theme.name.trim().isEmpty
            ? AppStrings.printSelectionAiLabel
            : image.theme.name);
    return Material(
      color: colors.cardBackgroundColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? colors.primaryColor : colors.borderColor,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(11)),
                  child: CachedNetworkImage(
                    imageUrl: image.imageUrl,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: selected
                          ? colors.primaryColor
                          : colors.secondaryTextColor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.textColor,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
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
    );
  }
}
