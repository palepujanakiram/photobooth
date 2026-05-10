import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoColors, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_settings_manager.dart';
import '../../services/kiosk_manager.dart';
import 'photo_generate_viewmodel.dart';
import '../theme_selection/theme_model.dart';
import '../../utils/constants.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/leading_with_alice.dart';
import '../../views/widgets/theme_background.dart';
import '../../utils/route_args.dart';
import '../../utils/secure_image_url.dart';
import '../../utils/transformation_step_display.dart';
import '../transformation_details/transformation_details_view.dart';
import '../../views/widgets/contact_before_pay_sheet.dart';
import '../../views/widgets/cached_network_image.dart';
import '../photo_capture/photo_image_from_xfile_io.dart'
    if (dart.library.html) '../photo_capture/photo_image_from_xfile_web.dart' as photo_image;

class PhotoGenerateScreen extends StatefulWidget {
  const PhotoGenerateScreen({super.key});

  @override
  State<PhotoGenerateScreen> createState() => _PhotoGenerateScreenState();
}

class _PhotoGenerateScreenState extends State<PhotoGenerateScreen> {
  /// Layout animations when zoom toggles (message strip, row height, footer shift).
  static const Duration _kZoomLayoutAnimationDuration =
      Duration(milliseconds: 280);
  static const Curve _kZoomLayoutAnimationCurve = Curves.easeOutCubic;

  /// Reserved height for Continue + “Or add one more style” so the bar stays fixed when cards zoom.
  static const double _kGenerateFooterSlotHeight = 140.0;

  /// AppBar [bottom]: subtitle line + optional stamp strip (must match [PreferredSize]).
  static const double _kBeholdSubtitleBlockHeight = 28.0;
  static const double _kBeholdStampStripExtraHeight = 62.0;

  double _beholdAppBarBelowTitleHeight(PhotoGenerateViewModel vm) {
    if (!vm.showProgressStampStrip) return _kBeholdSubtitleBlockHeight;
    return _kBeholdSubtitleBlockHeight + _kBeholdStampStripExtraHeight;
  }

  late PhotoGenerateViewModel _viewModel;
  bool _viewModelCreated = false;
  bool _isInitialized = false;
  final GlobalKey _contentKey = GlobalKey();

  bool? _paymentsEnabledOverride;

  /// At most one zoomed slot: null or a [GeneratedImage.id].
  String? _zoomedSlotId;

  void _clearPhotoZoom() {
    if (_zoomedSlotId == null) return;
    setState(() => _zoomedSlotId = null);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_viewModelCreated) {
      final rawArgs = ModalRoute.of(context)?.settings.arguments;
      if (rawArgs is PhotoGenerateViewModel) {
        // Result-only route: receive a fully initialized ViewModel from the
        // progress page (which ran generation).
        _viewModel = rawArgs;
        _viewModelCreated = true;
        _isInitialized = true;
        unawaited(_loadPaymentEnablement());
        return;
      }
      _viewModel = PhotoGenerateViewModel(
        appSettingsManager: context.read<AppSettingsManager>(),
      );
      _viewModelCreated = true;
      unawaited(_viewModel.loadProgressiveDisplayPreference());
      unawaited(_loadPaymentEnablement());
    }
    if (!_isInitialized) {
      _initializeFromArguments();
      _isInitialized = true;
    }
  }

  Future<void> _loadPaymentEnablement() async {
    final v = await KioskManager().getPaymentEnabledOverride();
    if (!mounted) return;
    setState(() => _paymentsEnabledOverride = v);
  }

  void _initializeFromArguments() {
    // `/generate` is now result-only. If someone navigates here with GenerateArgs,
    // redirect them to the progress route.
    final raw = ModalRoute.of(context)?.settings.arguments;
    final parsed = GenerateArgs.tryParse(raw);
    if (parsed == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        AppConstants.kRouteGenerateProgress,
        arguments: parsed,
      );
    });
  }

  // Note: We previously derived per-image aspect ratios. Now that we always show
  // generated outputs in a consistent grid, this is no longer needed.

  void _showCancelConfirmation(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancel Process?'),
          content: const Text(
            'Are you sure you want to cancel? Your generated images will be lost.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                Navigator.of(context).maybePop();
              },
              child: const Text('Yes', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _showCancelOperationDialog(BuildContext context, PhotoGenerateViewModel viewModel) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Cancel Generation?'),
          content: const Text(
            'An image is currently being generated. Do you want to cancel and go back?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Keep Waiting'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                viewModel.cancelOperation();
                Navigator.of(context).maybePop();
              },
              child: const Text('Cancel & Go Back', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  void _showRemoveStyleConfirmation(
    BuildContext context, {
    required String themeName,
    required VoidCallback onConfirm,
  }) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove this style?'),
          content: Text(
            'Remove "$themeName" from your generated photos? You can add it again later with "Add one more style".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                onConfirm();
              },
              child: const Text('Remove', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return ChangeNotifierProvider.value(
      value: _viewModel,
      child: Consumer<PhotoGenerateViewModel>(
        builder: (context, viewModel, child) {
          if (viewModel.hasError) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && viewModel.hasError) {
                AppSnackBar.showError(
                  context,
                  viewModel.errorMessage ?? 'Generation failed',
                );
                viewModel.clearError();
              }
            });
          }
          return Scaffold(
            backgroundColor: Colors.transparent,
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              forceMaterialTransparency: true,
              centerTitle: true,
              title: const Text(
                'BEHOLD',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 22,
                ),
              ),
              bottom: PreferredSize(
                preferredSize: Size.fromHeight(
                  _beholdAppBarBelowTitleHeight(viewModel),
                ),
                child: _buildBeholdAppBarBottom(context, viewModel),
              ),
              leading: IconButton(
                icon: const Icon(CupertinoIcons.back, color: Colors.white),
                onPressed: () {
                  _clearPhotoZoom();
                  if (viewModel.isOperationInProgress) {
                    _showCancelOperationDialog(context, viewModel);
                  } else {
                    _showCancelConfirmation(context);
                  }
                },
              ),
              actions: [
                IconButton(
                  tooltip: viewModel.useProgressiveGenerationUi
                      ? 'Switch to simple progress'
                      : 'Switch to stage previews',
                  icon: Icon(
                    viewModel.useProgressiveGenerationUi
                        ? Icons.view_compact
                        : Icons.view_timeline,
                    color: Colors.white,
                  ),
                    onPressed: () async {
                    await viewModel.toggleProgressiveGenerationUi();
                  },
                ),
                const AppBarAliceAction(),
              ],
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: ThemeBackground(theme: viewModel.selectedTheme),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top +
                          kToolbarHeight +
                          _beholdAppBarBelowTitleHeight(viewModel),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return _buildMainContent(
                                  context,
                                  viewModel,
                                  appColors,
                                  isLandscape,
                                  constraints.maxHeight,
                                  constraints.maxWidth,
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBeholdAppBarBottom(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
  ) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text(
            'Your AI-transformed portrait awaits',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  /// Device capture (“In frame”) + core API stages + optional Branded/Signed + storage.
  Widget _funnelPipelineStamp(
    PhotoGenerateViewModel viewModel,
    PipelineFunnelSlot slot,
    int index,
  ) {
    const thumb = 60.0;
    const outer = 68.0;
    final stampId = 'funnel:$index';
    final selected = viewModel.selectedHeroStampId == stampId;
    final url = slot.displayPreviewUrl;
    final statusLabel = slot.isFinished
        ? 'done'
        : slot.isActive
            ? 'in progress'
            : slot.isPending
                ? 'waiting'
                : 'queued';
    final borderColor = selected
        ? CupertinoColors.systemBlue
        : slot.isFinished
            ? Colors.lightGreenAccent.withValues(alpha: 0.85)
            : slot.isActive
                ? CupertinoColors.activeBlue
                : Colors.white30;
    final borderW = selected ? 2.5 : (slot.isActive ? 2.0 : 1.0);

    late final Widget inner;
    if (slot.isDeviceCapture) {
      final photo = viewModel.originalPhoto;
      if (photo != null) {
        inner = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: thumb,
            height: thumb,
            child: photo_image.imageFromXFileSized(
              photo.imageFile,
              thumb,
              thumb,
              fit: BoxFit.cover,
            ),
          ),
        );
      } else {
        inner = Icon(
          transformationStepIcon(slot.stageKey),
          color: Colors.white54,
          size: 32,
        );
      }
    } else if (url != null && url.isNotEmpty) {
      inner = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: SecureImageUrl.withSessionId(url),
          width: thumb,
          height: thumb,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
        ),
      );
    } else if (slot.isMetadataOnlyStage && slot.isFinished) {
      inner = Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            transformationStepIcon(slot.stageKey),
            color: Colors.white70,
            size: 32,
          ),
          Positioned(
            right: 1,
            bottom: 1,
            child: Icon(
              Icons.check_circle,
              color: Colors.lightGreenAccent.withValues(alpha: 0.95),
              size: 18,
            ),
          ),
        ],
      );
    } else if (slot.isMetadataOnlyStage && slot.isActive) {
      inner = Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            transformationStepIcon(slot.stageKey),
            color: Colors.white60,
            size: 32,
          ),
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
        ],
      );
    } else if (slot.isFinished) {
      inner = const Icon(Icons.check_circle,
          color: Colors.lightGreenAccent, size: 32);
    } else if (slot.isActive) {
      inner = const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        ),
      );
    } else {
      inner = Icon(Icons.image_outlined,
          color: Colors.white.withValues(alpha: 0.35), size: 32);
    }

    return Tooltip(
      message: '${slot.label} — $statusLabel',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => viewModel.toggleHeroStamp(stampId),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: outer,
            height: outer,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(width: borderW, color: borderColor),
              color: Colors.black.withValues(alpha: 0.35),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ColoredBox(
                color: Colors.black45,
                child: inner,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget? _generatingHeroUnderlay(PhotoGenerateViewModel vm) {
    final id = vm.selectedHeroStampId;
    if (id == null) return null;
    if (id == 'source' && vm.originalPhoto != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: photo_image.imageFromXFileSized(
            vm.originalPhoto!.imageFile,
            720,
            1280,
            fit: BoxFit.contain,
          ),
        ),
      );
    }
    if (id.startsWith('stage:')) {
      final key = id.substring(6);
      for (final s in vm.progressivePipelineStages) {
        if (s.stepKey == key) {
          final url = s.previewImageUrl;
          if (url != null && url.isNotEmpty) {
            return ColoredBox(
              color: Colors.black,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: SecureImageUrl.withSessionId(url),
                  fit: BoxFit.contain,
                ),
              ),
            );
          }
        }
      }
    }
    if (id.startsWith('live:')) {
      final idx = int.tryParse(id.substring(5));
      if (idx != null &&
          idx >= 0 &&
          idx < vm.liveSlots.length &&
          !vm.liveSlots[idx].loading) {
        final url = vm.liveSlots[idx].imageUrl;
        if (url != null && url.isNotEmpty) {
          return ColoredBox(
            color: Colors.black,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: SecureImageUrl.withSessionId(url),
                fit: BoxFit.contain,
              ),
            ),
          );
        }
      }
    }
    if (id.startsWith('funnel:')) {
      final idx = int.tryParse(id.substring(7));
      if (idx != null &&
          idx >= 0 &&
          idx < vm.pipelineFunnelSlots.length) {
        final slot = vm.pipelineFunnelSlots[idx];
        if (slot.isDeviceCapture && vm.originalPhoto != null) {
          return ColoredBox(
            color: Colors.black,
            child: Center(
              child: photo_image.imageFromXFileSized(
                vm.originalPhoto!.imageFile,
                720,
                1280,
                fit: BoxFit.contain,
              ),
            ),
          );
        }
        final url = slot.displayPreviewUrl;
        if (url != null && url.isNotEmpty) {
          return ColoredBox(
            color: Colors.black,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: SecureImageUrl.withSessionId(url),
                fit: BoxFit.contain,
              ),
            ),
          );
        }
        if (slot.isMetadataOnlyStage && slot.isFinished) {
          return ColoredBox(
            color: Colors.black,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    transformationStepIcon(slot.stageKey),
                    color: Colors.white70,
                    size: 72,
                  ),
                  const SizedBox(height: 16),
                  const Icon(
                    Icons.check_circle,
                    color: Colors.lightGreenAccent,
                    size: 48,
                  ),
                ],
              ),
            ),
          );
        }
        if (slot.isFinished) {
          return const ColoredBox(
            color: Colors.black,
            child: Center(
              child: Icon(
                Icons.check_circle,
                color: Colors.lightGreenAccent,
                size: 72,
              ),
            ),
          );
        }
      }
    }
    return null;
  }

  Widget _buildMainContent(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors, [
    bool isLandscape = false,
    double? viewportHeight,
    double? viewportWidth,
  ]) {
    final padding = isLandscape ? 12.0 : 16.0;
    final maxWidth = viewportWidth != null && viewportWidth.isFinite ? viewportWidth : double.infinity;

    Widget buildContent(double width) {
      final contentWidth = width.isFinite ? width : null;
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: Column(
              key: _contentKey,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildPhotosDisplay(
                  context,
                  viewModel,
                  appColors,
                  isLandscape,
                  contentWidth,
                  viewportHeight,
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (viewportHeight != null && viewportHeight > 0) {
      final hasFooter = viewModel.generatedImages.isNotEmpty ||
          viewModel.isGenerating;
      final footerH = hasFooter ? _kGenerateFooterSlotHeight : 0.0;

      return Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, slot) {
                  final w = slot.maxWidth.isFinite && slot.maxWidth > 0
                      ? slot.maxWidth
                      : maxWidth;
                  final contentW = w.isFinite ? w : null;
                  return Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: contentW,
                      child: _buildPhotosDisplay(
                        context,
                        viewModel,
                        appColors,
                        isLandscape,
                        contentW,
                        viewportHeight,
                        true,
                      ),
                    ),
                  );
                },
              ),
            ),
            if (hasFooter)
              SizedBox(
                height: footerH,
                child: Center(
                  child: _buildPhotosActionFooter(
                    context,
                    viewModel,
                    appColors,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(padding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth.isFinite ? constraints.maxWidth : maxWidth;
          return buildContent(w);
        },
      ),
    );
  }

  Widget _buildPhotosActionFooter(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
  ) {
    final paymentsEnabled = _paymentsEnabledOverride ?? true;
    final canAddMoreStyle = viewModel.canShowAddAnotherStyleButton;
    final isGenerating = viewModel.isGenerating && viewModel.generatedImages.isEmpty;
    final isLoadingMore = viewModel.isLoadingMore;
    final isGeneratingOrLoading = isGenerating || isLoadingMore;

    return SizedBox(
      width: 320,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(vertical: 16),
            color: (!isGeneratingOrLoading && viewModel.hasSelectedImages)
                ? CupertinoColors.systemBlue
                : CupertinoColors.systemGrey,
            borderRadius: BorderRadius.circular(12),
            onPressed: (!isGeneratingOrLoading && viewModel.hasSelectedImages)
                ? () async {
                    _clearPhotoZoom();
                    final selectedImages = viewModel.selectedGeneratedImages;
                    if (selectedImages.isEmpty) return;

                    final routerContext = context;
                    String customerName = '';
                    String customerPhone = '';
                    bool customerWhatsappOptIn = false;
                    if (paymentsEnabled) {
                      final contact = await showContactBeforePaySheet(routerContext);
                      if (!routerContext.mounted) return;
                      if (contact == null) return;
                      customerName = contact.customerName;
                      customerPhone = contact.customerPhone;
                      customerWhatsappOptIn = contact.whatsappOptIn;
                    }

                    await Navigator.pushNamed(
                      routerContext,
                      AppConstants.kRouteResult,
                      arguments: {
                        'generatedImages': selectedImages,
                        'originalPhoto': viewModel.originalPhoto,
                        'customerName': customerName,
                        'customerPhone': customerPhone,
                        'customerWhatsappOptIn': customerWhatsappOptIn,
                      },
                    );
                  }
                : null,
            child: Text(
              viewModel.selectedCount < viewModel.generatedImages.length
                  ? 'Continue (${viewModel.selectedCount} of ${viewModel.generatedImages.length})'
                  : 'Continue',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: CupertinoColors.white,
              ),
            ),
          ),
          if (!isGeneratingOrLoading &&
              viewModel.lastTransformationRunId != null &&
              viewModel.generatedImages.isNotEmpty) ...[
            TextButton(
              onPressed: () {
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => TransformationDetailsScreen(
                      runId: viewModel.lastTransformationRunId!,
                    ),
                  ),
                );
              },
              child: const Text(
                'Transformation details',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
          if (paymentsEnabled && viewModel.selectedCount > 0) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                'Total: ₹${viewModel.selectedTotalPrice}'
                '${viewModel.selectedCount > 1 ? '  (+₹${(viewModel.selectedCount - 1) * viewModel.additionalPrintPrice})' : ''}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (canAddMoreStyle) ...[
            const SizedBox(height: 8),
            Center(
              child: CupertinoButton(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                onPressed: (viewModel.isGenerating || viewModel.isLoadingMore)
                    ? null
                    : () async {
                        _clearPhotoZoom();
                        final result = await Navigator.pushNamed(
                          context,
                          AppConstants.kRouteHome,
                          arguments: {
                            if (viewModel.originalPhoto != null)
                              'photo': viewModel.originalPhoto,
                            'addOneMoreStyle': true,
                            'usedThemeIds': List<String>.from(
                              viewModel.generatedImages
                                  .map((e) => e.theme.id),
                            ),
                          },
                        );
                        if (!mounted) return;
                        if (result is ThemeModel) {
                          viewModel.prepareToAddStyle(result);
                          viewModel.tryDifferentStyle(result);
                        }
                      },
                child: const Text(
                  'Or add one more style',
                  style: TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.systemBlue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhotosDisplay(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors, [
    bool isLandscape = false,
    double? availableWidth,
    double? viewportHeight,
    bool fixedFooterOutside = false,
  ]) {
    // Slightly tighter padding so cards use more canvas (kiosk-friendly).
    final double sectionPadding = isLandscape ? 10.0 : 12.0;
    final screenWidth = availableWidth ??
        (MediaQuery.sizeOf(context).width - 2 * sectionPadding).clamp(0.0, double.infinity);

    const double cardGap = 10.0;
    // Printing target is 6×4 => 3:2. Keep the generation/review canvas aligned to print.
    const double aspect = 3 / 2;

    final bool isGenerating = viewModel.isGenerating && viewModel.generatedImages.isEmpty;
    final bool isLoadingMore = viewModel.isLoadingMore;
    final bool isGeneratingOrLoading = isGenerating || isLoadingMore;

    final double vh = viewportHeight ?? MediaQuery.sizeOf(context).height;
    // Reduce reserved space so the photo canvas gets more prominence.
    const double reservedAboveRow = 72.0;
    const double reservedBelowRow = 172.0;
    // Landscape / large displays: let the photo row use more vertical space (kiosk).
    final double heightFraction = isLandscape ? 0.80 : 0.68;
    final double maxRowCap = isLandscape ? 1080.0 : 920.0;
    final double minRow = isLandscape ? 300.0 : 260.0;
    final double maxRowHeight = math.max(
      minRow,
      math.min(
        maxRowCap,
        math.min(
          vh * heightFraction,
          vh - reservedAboveRow - reservedBelowRow,
        ),
      ),
    );
    return _buildGeneratedOnlyLayout(
      context,
      viewModel,
      appColors,
      screenWidth: screenWidth,
      maxRowHeight: maxRowHeight,
      gap: cardGap,
      aspect: aspect,
      isGeneratingOrLoading: isGeneratingOrLoading,
      fixedFooterOutside: fixedFooterOutside,
    );
  }

  Widget _buildGeneratedOnlyLayout(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors, {
    required double screenWidth,
    required double maxRowHeight,
    required double gap,
    required double aspect,
    required bool isGeneratingOrLoading,
    required bool fixedFooterOutside,
  }) {
    final isGenerating = viewModel.isGenerating && viewModel.generatedImages.isEmpty;
    final isLoadingMore = viewModel.isLoadingMore;
    final images = viewModel.generatedImages;
    final hasImages = images.isNotEmpty;
    final hideCompactHeader = viewModel.useProgressiveGenerationLayoutForSession &&
        isGeneratingOrLoading;

    final int baseSlotCount = hasImages
        ? images.length
        : (isGenerating && viewModel.liveSlotCount > 0
            ? viewModel.liveSlotCount
            : 1);
    final totalSlots = baseSlotCount + (isLoadingMore ? 1 : 0);

    // When we only have a single slot (initial placeholder or one image),
    // size it like the POSE capture card so the "main image placeholder" feels consistent.
    if (totalSlots == 1) {
      // Use the same aspect-fit sizing as POSE, but don't over-cap on BEHOLD:
      // `maxRowHeight` already accounts for reserved header/footer space.
      final maxW = screenWidth;
      final maxH = maxRowHeight;

      late double cardW;
      late double cardH;
      if (maxW / maxH > aspect) {
        cardH = maxH;
        cardW = cardH * aspect;
      } else {
        cardW = maxW;
        cardH = cardW / aspect;
      }

      final String? genZoomId = _zoomedSlotId != null &&
              viewModel.generatedImages.any((e) => e.id == _zoomedSlotId)
          ? _zoomedSlotId
          : null;

      final slots = _buildTransformedSlotWidgets(
        context,
        viewModel,
        appColors,
        cardW,
        cardH,
        genZoomId,
      );

      final isGenerating = viewModel.isGenerating && viewModel.generatedImages.isEmpty;
      final isLoadingMore = viewModel.isLoadingMore;
      final message = isGeneratingOrLoading
          ? (isLoadingMore
              ? 'Adding your new style...'
              : 'Please wait while we create your masterpiece')
          : hasImages
              ? 'Your masterpiece is ready'
              : '';

      final wideStoryLayout = MediaQuery.sizeOf(context).width >= 980;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hideCompactHeader &&
                isGeneratingOrLoading &&
                !viewModel.showProgressStampStrip) ...[
              _buildProgressivePipelineSection(context, viewModel),
              const SizedBox(height: 12),
            ] else if (!hideCompactHeader &&
                isGenerating &&
                viewModel.liveSlotCount > 0) ...[
              _buildLiveGenerationHeader(context, viewModel),
              const SizedBox(height: 12),
            ],
            if (message.isNotEmpty) ...[
              Text(
                message,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (hasImages && !isGeneratingOrLoading) ...[
                const SizedBox(height: 6),
                Text(
                  'Generated in ${viewModel.elapsedSeconds}s',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 18),
            ],
            if (isGeneratingOrLoading && !hasImages) ...[
              // In-progress uses the same hero card visual language as final output.
              _buildGenerationProgressHeroCard(
                context,
                viewModel,
                width: maxW,
                height: cardH,
              ),
            ] else if (wideStoryLayout && isGeneratingOrLoading) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Center(child: slots.first),
                  const SizedBox(width: 18),
                  _buildGenerationStoryCard(context, viewModel),
                ],
              ),
            ] else ...[
              Center(child: slots.first),
              if (isGeneratingOrLoading) ...[
                const SizedBox(height: 18),
                _buildGenerationStoryCard(context, viewModel),
              ],
            ],
            if ((hasImages || isGenerating || isLoadingMore) &&
                !fixedFooterOutside) ...[
              const SizedBox(height: 18),
              _buildPhotosActionFooter(context, viewModel, appColors),
            ],
          ],
        ),
      );
    }

    // Responsive grid: 1 -> 1 col, 2 -> 2 cols, 3+ -> 3 cols (clamped by width).
    int cols = totalSlots <= 1 ? 1 : (totalSlots == 2 ? 2 : 3);
    cols = cols.clamp(1, 3);
    final rows = (totalSlots / cols).ceil().clamp(1, 3);

    // Compute card sizes from height budget; scale down if width would overflow.
    final gridH = maxRowHeight;
    final cardH = (gridH - gap * (rows - 1)) / rows;
    final cardW = cardH * aspect;
    final gridW = cols * cardW + gap * (cols - 1);
    final scale = gridW > screenWidth ? (screenWidth / gridW).clamp(0.35, 1.0) : 1.0;
    final scaledW = cardW * scale;
    final scaledH = cardH * scale;

    final String? genZoomId = _zoomedSlotId != null &&
            viewModel.generatedImages.any((e) => e.id == _zoomedSlotId)
        ? _zoomedSlotId
        : null;

    final slots = _buildTransformedSlotWidgets(
      context,
      viewModel,
      appColors,
      scaledW,
      scaledH,
      genZoomId,
    );

    final message = isGeneratingOrLoading
        ? (isLoadingMore
            ? 'Adding your new style...'
            : 'Please wait while we create your masterpiece')
        : hasImages
            ? 'Your masterpiece is ready'
            : '';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hideCompactHeader &&
              isGeneratingOrLoading &&
              !viewModel.showProgressStampStrip) ...[
            _buildProgressivePipelineSection(context, viewModel),
            const SizedBox(height: 12),
          ] else if (!hideCompactHeader &&
              isGenerating &&
              viewModel.liveSlotCount > 0) ...[
            _buildLiveGenerationHeader(context, viewModel),
            const SizedBox(height: 12),
          ],
          if (message.isNotEmpty) ...[
            Text(
              message,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 18),
          ],
          AnimatedSize(
            duration: _kZoomLayoutAnimationDuration,
            curve: _kZoomLayoutAnimationCurve,
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            child: SizedBox(
              width: screenWidth,
              child: Center(
                child: Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  alignment: WrapAlignment.center,
                  children: slots,
                ),
              ),
            ),
          ),
          if ((hasImages || isGenerating || isLoadingMore) && !fixedFooterOutside) ...[
            const SizedBox(height: 18),
            _buildPhotosActionFooter(context, viewModel, appColors),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildTransformedSlotWidgets(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
    double cardWidth,
    double cardHeight,
    String? effectiveZoomId,
  ) {
    final isGenerating = viewModel.isGenerating && viewModel.generatedImages.isEmpty;
    final isLoadingMore = viewModel.isLoadingMore;
    final images = viewModel.generatedImages;
    final hasImages = images.isNotEmpty;

    if (isGenerating && !hasImages && viewModel.liveSlotCount > 0) {
      return viewModel.liveSlots
          .map(
            (slot) => _transformedSlotFrame(
              cardWidth: cardWidth,
              cardHeight: cardHeight,
              child: _buildLiveGenerationSlot(
                viewModel,
                appColors,
                slot,
              ),
            ),
          )
          .toList();
    }

    if (isGenerating && !hasImages) {
      return [
        _transformedSlotFrame(
          cardWidth: cardWidth,
          cardHeight: cardHeight,
          child: _buildTransformedLoadingPlaceholder(viewModel, appColors),
        ),
      ];
    }

    if (!hasImages) {
      return [
        _transformedSlotFrame(
          cardWidth: cardWidth,
          cardHeight: cardHeight,
          child: const Center(
            child: Icon(
              Icons.photo_outlined,
              size: 48,
              color: Colors.white54,
            ),
          ),
        ),
      ];
    }

    const bool showRemoveButton = false;
    final out = <Widget>[];
    if (isLoadingMore) {
      out.add(
        _transformedSlotFrame(
          cardWidth: cardWidth,
          cardHeight: cardHeight,
          child: _buildTransformedLoadingPlaceholder(viewModel, appColors),
        ),
      );
    }
    for (final image in images) {
      out.add(
        _buildOneTransformedImageCard(
          context,
          viewModel,
          image,
          cardWidth,
          cardHeight,
          effectiveZoomId: effectiveZoomId,
          showRemoveButton: showRemoveButton,
        ),
      );
    }
    return out;
  }

  Widget _transformedSlotFrame({
    required double cardWidth,
    required double cardHeight,
    required Widget child,
  }) {
    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: child,
        ),
      ),
    );
  }

  Widget _buildOneTransformedImageCard(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    GeneratedImage image,
    double cardWidth,
    double cardHeight, {
    required String? effectiveZoomId,
    bool showRemoveButton = false,
  }) {
    final isZoomed = effectiveZoomId == image.id;
    const double zoom = AppConstants.kGeneratePhotoZoomedScale;
    final double slotW = isZoomed ? cardWidth * zoom : cardWidth;
    final double slotH = isZoomed ? cardHeight * zoom : cardHeight;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: slotW,
      height: slotH,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() {
            _zoomedSlotId = _zoomedSlotId == image.id ? null : image.id;
          });
        },
        child: SizedBox.expand(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: image.isSelected
                    ? CupertinoColors.systemBlue.withValues(alpha: 0.85)
                    : Colors.white24,
                width: image.isSelected ? 2.0 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                fit: StackFit.expand,
                children: [
                if (image.isSelected)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          boxShadow: [
                            BoxShadow(
                              color: CupertinoColors.systemBlue.withValues(alpha: 0.18),
                              blurRadius: 26,
                              spreadRadius: 2,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                const ColoredBox(color: Colors.black),
                Image.network(
                  SecureImageUrl.withSessionId(image.imageUrl),
                  // Show the full generation in-frame (no crop).
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  width: double.infinity,
                  height: double.infinity,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(
                      CupertinoIcons.exclamationmark_triangle,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
                if (showRemoveButton)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Material(
                      color: Colors.white,
                      elevation: 2,
                      shadowColor: Colors.black38,
                      shape: const CircleBorder(),
                      child: InkWell(
                        onTap: () => _showRemoveStyleConfirmation(
                          context,
                          themeName: image.theme.name,
                          onConfirm: () =>
                              viewModel.removeGeneratedImage(image.id),
                        ),
                        customBorder: const CircleBorder(),
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            CupertinoIcons.trash_fill,
                            color: Colors.black87,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => viewModel.toggleImageSelection(image.id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: image.isSelected
                              ? CupertinoColors.systemBlue.withValues(alpha: 0.92)
                              : Colors.black.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: image.isSelected
                                ? Colors.white.withValues(alpha: 0.25)
                                : Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              image.isSelected
                                  ? CupertinoIcons.check_mark
                                  : CupertinoIcons.circle,
                              size: 14,
                              color: Colors.white,
                            ),
                            if (image.isSelected) ...[
                              const SizedBox(width: 6),
                              const Text(
                                'Selected',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  height: 1.0,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.7),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Text(
                      image.theme.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildProgressivePipelineSection(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
  ) {
    final stages = viewModel.progressivePipelineStages;
    final progress = (viewModel.liveProgress / 100).clamp(0.0, 1.0);
    final caption = viewModel.progressiveOneLiner;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress <= 0 ? null : progress,
              minHeight: 6,
              backgroundColor: Colors.white24,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 118,
            child: stages.isEmpty
                ? Center(
                    child: Text(
                      'Pipeline starting — watch each stage appear here.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: stages.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      return _buildProgressiveStageTile(context, stages[i]);
                    },
                  ),
          ),
          if (caption != null && caption.isNotEmpty) ...[
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: Text(
                caption,
                key: ValueKey<String>(caption),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  height: 1.25,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressiveStageTile(
    BuildContext context,
    ProgressivePipelineStage stage,
  ) {
    final label = transformationStepDisplayLabel(stage.stepKey);
    final url = stage.previewImageUrl;

    Widget thumb;
    if (url != null && url.isNotEmpty) {
      thumb = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: CachedNetworkImage(
          imageUrl: SecureImageUrl.withSessionId(url),
          fit: BoxFit.cover,
          width: 72,
          height: 72,
        ),
      );
    } else if (stage.complete && !stage.skipped) {
      thumb = Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: const Icon(Icons.check_circle, color: Colors.lightGreenAccent, size: 36),
      );
    } else if (stage.skipped) {
      thumb = Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: const Icon(Icons.skip_next, color: Colors.white38, size: 32),
      );
    } else if (stage.active) {
      thumb = Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amberAccent, width: 2),
        ),
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          ),
        ),
      );
    } else {
      thumb = Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Icon(
          transformationStepIcon(stage.stepKey),
          color: Colors.white38,
          size: 32,
        ),
      );
    }

    return SizedBox(
      width: 82,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          thumb,
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: stage.skipped ? Colors.white38 : Colors.white70,
              fontSize: 10,
              decoration:
                  stage.skipped ? TextDecoration.lineThrough : TextDecoration.none,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          if (stage.durationMs != null && stage.complete)
            Text(
              '${stage.durationMs} ms',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 9,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLiveGenerationHeader(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
  ) {
    final step = viewModel.liveCurrentStep;
    final commentary = viewModel.liveCommentary;
    final attempt = viewModel.liveAttempt;
    final totalAttempts = viewModel.liveTotalAttempts;
    final lastScore = viewModel.liveLastScore;
    final progress = (viewModel.liveProgress / 100).clamp(0.0, 1.0);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress <= 0 ? null : progress,
              minHeight: 6,
              backgroundColor: Colors.white24,
              color: Colors.white,
            ),
          ),
          if (step != null && step.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Step: ${transformationStepDisplayLabel(step)}'
              '${viewModel.liveStepDurationsMs[step] != null ? ' · ${viewModel.liveStepDurationsMs[step]} ms' : ''}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (attempt != null &&
              totalAttempts != null &&
              totalAttempts > 1) ...[
            const SizedBox(height: 6),
            Text(
              'Attempt $attempt of $totalAttempts'
              '${lastScore != null ? ' · last score ${lastScore.toStringAsFixed(2)}' : ''}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          if (commentary != null && commentary.isNotEmpty) ...[
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: Text(
                commentary,
                key: ValueKey<String>(commentary),
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveGenerationSlot(
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
    LiveGenerationSlotState slot,
  ) {
    if (slot.loading) {
      return _buildTransformedLoadingPlaceholder(viewModel, appColors);
    }
    if (slot.failed) {
      return const Center(
        child: Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
      );
    }
    final url = slot.imageUrl;
    if (url == null || url.isEmpty) {
      return const Center(
        child: Icon(Icons.image_not_supported_outlined,
            color: Colors.white38, size: 40),
      );
    }
    final secureUrl = SecureImageUrl.withSessionId(url);
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: secureUrl,
          fit: BoxFit.cover,
        ),
        if (slot.qualityScore != null)
          Positioned(
            top: 8,
            right: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  slot.qualityScore!.toStringAsFixed(2),
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTransformedLoadingPlaceholder(
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
  ) {
    final message = viewModel.progressMessage.isNotEmpty
        ? viewModel.progressMessage
        : (viewModel.isLoadingMore ? 'Adding new style...' : 'Creating...');
    final underlay = _generatingHeroUnderlay(viewModel);
    final hint = viewModel.selectedHeroStampId != null &&
            underlay == null
        ? 'Preview not ready for this step yet'
        : null;
    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (underlay != null) Positioned.fill(child: underlay),
          Positioned.fill(
            child: ColoredBox(
              color: underlay != null
                  ? Colors.black.withValues(alpha: 0.42)
                  : Colors.black26,
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 12),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      hint,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    '${viewModel.elapsedSeconds}s',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenerationStoryCard(
    BuildContext context,
    PhotoGenerateViewModel vm,
  ) {
    final slots = vm.pipelineFunnelSlots;
    if (slots.isEmpty) return const SizedBox.shrink();
    final screenW = MediaQuery.sizeOf(context).width;
    final maxW = math.min(screenW * 0.44, 560.0);

    // ThemeCard-like visual language (kiosk presentation).
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxW),
      child: Card(
        elevation: 10,
        shadowColor: CupertinoColors.systemBlue.withValues(alpha: 0.22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF4A4A4A), width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.black.withValues(alpha: 0.78),
                Colors.black.withValues(alpha: 0.52),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(CupertinoIcons.sparkles,
                        color: Colors.white70, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'AI generation',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      '${(vm.pipelineFunnelProgress * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 68,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: slots.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) => _funnelPipelineStamp(vm, slots[i], i),
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: vm.pipelineFunnelProgress,
                    minHeight: 10,
                    backgroundColor: Colors.white24,
                    color: CupertinoColors.systemBlue,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  vm.progressMessage.isNotEmpty
                      ? vm.progressMessage
                      : 'Transforming your look…',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.left,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGenerationProgressHeroCard(
    BuildContext context,
    PhotoGenerateViewModel vm, {
    required double width,
    required double height,
  }) {
    // Use the same hero frame as the final image card; swap the "content" inside.
    final preprocessUrl = _previewForStage(vm, 'preprocessing');
    final bgUrl = _previewForStage(vm, 'background_removal');
    final aiUrl = _previewForStage(vm, 'ai_generation');

    int index = 0;
    String stageTitle = '2 · CAPTURE';
    String headline = 'Got it';
    String description = 'Frozen frame, framing applied';
    String? imageUrl;
    Widget? bottomAccessory;

    if (aiUrl != null) {
      index = 3;
      stageTitle = '4 · REVEAL';
      headline = 'Rendering';
      description = 'AI is applying your style';
      imageUrl = aiUrl;
      bottomAccessory = _buildPostRevealPolishingOverlay(context, vm);
    } else if (bgUrl != null) {
      index = 2;
      stageTitle = '3 · ISOLATE';
      headline = 'Background removed';
      description = 'Subject isolated, ready to render';
      imageUrl = bgUrl;
    } else if (preprocessUrl != null) {
      index = 1;
      stageTitle = '2 · CAPTURE';
      headline = 'Got it';
      description = 'Frozen frame, framing applied';
      imageUrl = preprocessUrl;
    } else {
      index = 0;
      stageTitle = '1 · DETECT';
      headline = 'Face locked';
      description = 'Live preview';
    }

    // Important UX: keep the photo canvas clean (no UI overlays).
    // All progress/status UI lives around the canvas, not on top of it.
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  stageTitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                  textAlign: TextAlign.left,
                ),
                const SizedBox(height: 8),
                _storyboardTopBars(activeIndex: index),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: width,
            height: height,
            child: _transformedSlotFrame(
              cardWidth: width,
              cardHeight: height,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: Colors.black),
                  Positioned.fill(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeOutCubic,
                      transitionBuilder: (child, anim) {
                        final fade = CurvedAnimation(
                          parent: anim,
                          curve: Curves.easeOut,
                        );
                        final scale =
                            Tween<double>(begin: 0.985, end: 1.0).animate(fade);
                        return FadeTransition(
                          opacity: fade,
                          child: ScaleTransition(scale: scale, child: child),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey<String>(imageUrl ?? 'local_$index'),
                        child: _buildProgressHeroStageImage(
                          context,
                          vm,
                          imageUrl: imageUrl,
                          width: width,
                          height: height,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  headline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  '${vm.elapsedSeconds}s',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (bottomAccessory != null) ...[
                  const SizedBox(height: 12),
                  bottomAccessory,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressHeroStageImage(
    BuildContext context,
    PhotoGenerateViewModel vm, {
    required String? imageUrl,
    required double width,
    required double height,
  }) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheW = (width * dpr).ceil().clamp(64, 2048);
    final loading = ColoredBox(
      color: Colors.black,
      child: SizedBox(
        width: width,
        height: height,
        child: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2,
            ),
          ),
        ),
      ),
    );
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final err = SizedBox(
        width: width,
        height: height,
        child: vm.originalPhoto != null
            ? photo_image.imageFromXFileSized(
                vm.originalPhoto!.imageFile,
                width,
                height,
                fit: BoxFit.cover,
              )
            : loading,
      );
      return SizedBox(
        width: width,
        height: height,
        child: ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            child: CachedNetworkImage(
              imageUrl: imageUrl.trim(),
              fit: BoxFit.cover,
              cacheWidth: cacheW,
              filterQuality: FilterQuality.medium,
              placeholder: loading,
              errorWidget: err,
            ),
          ),
        ),
      );
    }
    if (vm.originalPhoto != null) {
      return photo_image.imageFromXFileSized(
        vm.originalPhoto!.imageFile,
        width,
        height,
        fit: BoxFit.cover,
      );
    }
    return loading;
  }

  String? _previewForStage(PhotoGenerateViewModel vm, String stageKey) {
    final want = stageKey.trim().toLowerCase();
    for (final s in vm.generationRunStepPreviews) {
      final key = canonicalPipelineStageKey(s.stage);
      if (key == want && (s.previewUrl ?? '').trim().isNotEmpty) {
        return s.previewUrl!.trim();
      }
    }
    return null;
  }

  Widget _buildPostRevealPolishingOverlay(
    BuildContext context,
    PhotoGenerateViewModel vm,
  ) {
    // After REVEAL (ai_generation preview), keep users engaged by showing truthful
    // post-processing mechanics as `steps[]` advances.
    final steps = vm.generationRunStepPreviews;
    if (steps.isEmpty) return const SizedBox.shrink();

    final byStage = <String, GenerationRunStepPreview>{};
    for (final s in steps) {
      byStage[canonicalPipelineStageKey(s.stage)] = s;
    }

    const polishOrder = <String>[
      'scene_lighting',
      'face_relight',
      'frame_composite',
      'upscaling',
      'exif_stamp',
      'c2pa_sign',
      'storage',
    ];

    String? activeKey;
    for (final k in polishOrder) {
      final s = byStage[k];
      if (s != null && s.isActive) {
        activeKey = k;
        break;
      }
    }
    activeKey ??= byStage['storage']?.isFinished == true
        ? 'storage'
        : (polishOrder.firstWhere(
            (k) => byStage[k]?.isFinished != true,
            orElse: () => 'storage',
          ));

    String copyFor(String k) {
      switch (k) {
        case 'scene_lighting':
          return 'Matching scene lighting';
        case 'face_relight':
          return 'Relighting your face';
        case 'frame_composite':
          return 'Adding your frame';
        case 'upscaling':
          return 'Sharpening for print';
        case 'exif_stamp':
          return 'Branding';
        case 'c2pa_sign':
          return 'Signing authenticity';
        case 'storage':
          return 'Preparing print file';
        default:
          return transformationStepDisplayLabel(k);
      }
    }

    Widget stageChip(String k) {
      final s = byStage[k];
      final finished = s?.isFinished == true;
      final active = s?.isActive == true;
      final color = active
          ? CupertinoColors.activeBlue
          : finished
              ? Colors.lightGreenAccent.withValues(alpha: 0.9)
              : Colors.white30;
      final icon = finished
          ? Icons.check_circle
          : active
              ? Icons.autorenew
              : Icons.more_horiz;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.85), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              copyFor(k),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    // Sits in the storyboard’s bottom column (not centered on the photo).
    // Elapsed time stays on the frame’s corner badge to avoid duplicate timers.
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(CupertinoIcons.wand_stars,
                      color: Colors.white70, size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Finishing touches · ${copyFor(activeKey)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < polishOrder.length; i++) ...[
                      if (i != 0) const SizedBox(width: 8),
                      stageChip(polishOrder[i]),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _storyboardTopBars({required int activeIndex}) {
    const total = 4;
    return SizedBox(
      height: 10,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < total; i++) ...[
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: i == activeIndex ? 42 : 22,
              height: 6,
              decoration: BoxDecoration(
                color: i <= activeIndex
                    ? CupertinoColors.systemBlue
                    : Colors.white24,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            if (i != total - 1) const SizedBox(width: 10),
          ],
        ],
      ),
    );
  }

}

