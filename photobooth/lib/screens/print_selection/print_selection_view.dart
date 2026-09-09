import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_settings_manager.dart';
import '../../services/print_selection_coordinator.dart';
import '../../services/session_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/print_size_helpers.dart';
import '../../utils/route_args.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_theme.dart';
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
  bool _canEditLook = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_viewModel != null) return;
    final raw = ModalRoute.of(context)?.settings.arguments;
    final args = PrintSelectionArgs.tryParse(raw);
    final coordinator = PrintSelectionCoordinator.instance;
    final images = args?.generatedImages ??
        List<GeneratedImage>.from(coordinator.images);
    _canEditLook = args?.canEditLook == true ||
        (coordinator.fromClassicStrip && Navigator.of(context).canPop());
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

  void _editLook() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
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
    final orientation = SessionManager().printOrientation;
    final selected = ensureGeneratedImagePrintSizes(
      vm.selectedImages,
      orientation: orientation,
    );
    if (selected.isEmpty) return;
    if (!mounted) return;
    PrintSelectionCoordinator.instance.awaitingExploreMoreReturn = false;
    final runId = vm.transformationRunId?.trim();
    // Finalize: drop Pick your look + this hub so checkout cannot bounce back
    // into an unfinalized edit session.
    await Navigator.of(context).pushNamedAndRemoveUntil(
      AppConstants.kRouteResult,
      (route) =>
          route.settings.name == AppConstants.kRouteExperienceChoice ||
          route.settings.name == AppConstants.kRouteTerms ||
          route.settings.name == AppConstants.kRouteHome ||
          route.isFirst,
      arguments: ResultArgs(
        generatedImages: selected,
        printOrientation: orientation,
        transformationRunId:
            (runId != null && runId.isNotEmpty) ? runId : null,
        printSize: resolveClassicCheckoutSessionPrintSize(
          selected: selected,
          stripPrintSize: vm.stripPrintSize,
          classicComposeShotCount:
              PrintSelectionCoordinator.instance.classicComposeShotCount,
          orientation: orientation,
        ),
        classicComposeShotCount:
            PrintSelectionCoordinator.instance.classicComposeShotCount,
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
    final canEditLook = _canEditLook && Navigator.of(context).canPop();
    return ChangeNotifierProvider.value(
      value: vm,
      child: Scaffold(
        backgroundColor: colors.backgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: canEditLook
              ? IconButton(
                  icon: Icon(Icons.arrow_back, color: colors.textColor),
                  tooltip: AppStrings.printSelectionEditLook,
                  onPressed: _editLook,
                )
              : null,
          automaticallyImplyLeading: false,
          title: Text(
            AppStrings.printSelectionTitle,
            style: TextStyle(
              color: colors.textColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          centerTitle: true,
          actions: [
            if (canEditLook)
              TextButton(
                onPressed: _editLook,
                child: Text(
                  AppStrings.printSelectionEditLook,
                  style: TextStyle(
                    color: colors.primaryColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
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
                      AppStrings.printSelectionSubtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: colors.secondaryTextColor,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final count = vm.images.length;
                          if (count == 1) {
                            return _PrintSelectionFittedSheet(
                              image: vm.images.first,
                              isStrip: vm.isStripImage(vm.images.first),
                              isClassicSheet:
                                  vm.isClassicSingleSheet(vm.images.first),
                              printSize: vm.images.first.printSize ??
                                  vm.stripPrintSize,
                              onTap: () =>
                                  vm.toggleSelected(vm.images.first.id),
                            );
                          }
                          return GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.72,
                            ),
                            itemCount: count,
                            itemBuilder: (context, index) {
                              final image = vm.images[index];
                              return _PrintSelectionTile(
                                image: image,
                                isStrip: vm.isStripImage(image),
                                isClassicSheet:
                                    vm.isClassicSingleSheet(image),
                                onTap: () => vm.toggleSelected(image.id),
                              );
                            },
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
                    // Match theme / Classic look CTAs: full-width, 56pt, 14 radius.
                    AppContinueButton(
                      text: AppStrings.printSelectionContinue(vm.selectedCount),
                      onPressed: vm.canContinue ? _continueToPay : null,
                      height: 56,
                      padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
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

class _PrintSelectionFittedSheet extends StatelessWidget {
  const _PrintSelectionFittedSheet({
    required this.image,
    required this.isStrip,
    required this.isClassicSheet,
    required this.printSize,
    required this.onTap,
  });

  final GeneratedImage image;
  final bool isStrip;
  final bool isClassicSheet;
  final String? printSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = fitPrintSelectionTile(
          maxWidth: constraints.maxWidth,
          maxHeight: constraints.maxHeight,
          printAspectWidthOverHeight: printSelectionThumbAspectRatio(printSize),
        );
        if (size.width <= 0 || size.height <= 0) {
          return const SizedBox.shrink();
        }
        return Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: _PrintSelectionTile(
              image: image,
              isStrip: isStrip,
              isClassicSheet: isClassicSheet,
              onTap: onTap,
            ),
          ),
        );
      },
    );
  }
}

class _PrintSelectionTile extends StatelessWidget {
  const _PrintSelectionTile({
    required this.image,
    required this.isStrip,
    required this.isClassicSheet,
    required this.onTap,
  });

  final GeneratedImage image;
  final bool isStrip;
  final bool isClassicSheet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final selected = image.isSelected;
    final label = isStrip
        ? AppStrings.printSelectionStripLabel
        : (isClassicSheet
            ? AppStrings.printSelectionClassicLabel
            : (image.theme.name.trim().isEmpty
                ? AppStrings.printSelectionAiLabel
                : image.theme.name));
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
                  child: ColoredBox(
                    color: colors.backgroundColor,
                    child: CachedNetworkImage(
                      imageUrl: image.imageUrl,
                      // Full print — cover was cropping 4×6 differently than
                      // the look-picker preview the guest just approved.
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
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
