import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoColors, CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/app_settings_manager.dart';
import '../../services/kiosk_manager.dart';
import 'photo_generate_viewmodel.dart';
import 'post_reveal_polishing_overlay.dart';
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
import '../../views/widgets/generated_image_preview_screen.dart';
import '../photo_capture/photo_image_from_xfile_io.dart'
    if (dart.library.html) '../photo_capture/photo_image_from_xfile_web.dart' as photo_image;

// --- Pipeline funnel / “Behold” grid helpers (Sonar S3358 / S3776 extractions) ---

/// Short status text under each funnel thumbnail (queued → in progress → done).
String _funnelSlotStatusLabel(PipelineFunnelSlot slot) {
  if (slot.isFinished) return 'done';
  if (slot.isActive) return 'in progress';
  if (slot.isPending) return 'waiting';
  return 'queued';
}

/// Border color for funnel cells: selection overrides pipeline state colors.
Color _funnelSlotBorderColor(PipelineFunnelSlot slot, bool selected) {
  if (selected) return CupertinoColors.systemBlue;
  if (slot.isFinished) {
    return Colors.lightGreenAccent.withValues(alpha: 0.85);
  }
  if (slot.isActive) return CupertinoColors.activeBlue;
  return Colors.white30;
}

/// Thicker border when the slot is selected or actively generating.
double _funnelSlotBorderWidth(PipelineFunnelSlot slot, bool selected) {
  if (selected) return 2.5;
  if (slot.isActive) return 2.0;
  return 1.0;
}

/// How many grid placeholders to show before images arrive (live pipeline vs static).
int _beholdBaseSlotCount({
  required bool hasImages,
  required int imageCount,
  required bool isGenerating,
  required int liveSlotCount,
}) {
  if (hasImages) return imageCount;
  if (isGenerating && liveSlotCount > 0) return liveSlotCount;
  return 1;
}

/// Headline above the generated-image grid (loading vs ready vs empty).
String _beholdHeroMessage({
  required bool isGeneratingOrLoading,
  required bool isLoadingMore,
  required bool hasImages,
}) {
  if (isGeneratingOrLoading) {
    if (isLoadingMore) return 'Adding your new style...';
    return 'Please wait while we create your masterpiece';
  }
  if (hasImages) return 'Your masterpiece is ready';
  return '';
}

/// Vertical space reserved above the behold card when the footer is external.
String _transformedLoadingMessage(PhotoGenerateViewModel viewModel) {
  if (viewModel.progressMessage.isNotEmpty) {
    return viewModel.progressMessage;
  }
  if (viewModel.isLoadingMore) return 'Adding new style...';
  return 'Creating...';
}

/// Layout inputs for [_PhotoGenerateViewState._buildGeneratedOnlyLayout] (Sonar S107).
class _GeneratedOnlyLayoutLayout {
  const _GeneratedOnlyLayoutLayout({
    required this.screenWidth,
    required this.maxRowHeight,
    required this.gap,
    required this.isGeneratingOrLoading,
    required this.fixedFooterOutside,
  });

  final double screenWidth;
  final double maxRowHeight;
  final double gap;
  final bool isGeneratingOrLoading;
  final bool fixedFooterOutside;
}

double _computeBeholdMaxRowHeight({
  required bool fixedFooterOutside,
  required bool singleResultReady,
  required double viewportHeight,
  required double interiorChromeAboveCard,
  required bool isLandscape,
  required double reservedAboveRow,
  required double reservedBelowRow,
}) {
  if (fixedFooterOutside && singleResultReady) {
    return math.max(
      200.0,
      (viewportHeight - interiorChromeAboveCard) *
          AppConstants.kBeholdResultCardSlotHeightFraction,
    );
  }
  final heightFraction = isLandscape ? 0.80 : 0.68;
  final maxRowCap = isLandscape ? 1080.0 : 920.0;
  final rowBudget = math.min(
    maxRowCap,
    math.min(
      viewportHeight * heightFraction,
      viewportHeight -
          reservedAboveRow -
          reservedBelowRow -
          interiorChromeAboveCard,
    ),
  );
  return math.max(120.0, rowBudget);
}

double _interiorChromeAboveCardHeight({
  required bool fixedFooterOutside,
  required double? viewportHeight,
  required bool hasImages,
  required bool isGeneratingOrLoading,
}) {
  if (!fixedFooterOutside ||
      viewportHeight == null ||
      !viewportHeight.isFinite) {
    return 0.0;
  }
  if (hasImages && !isGeneratingOrLoading) return 118.0;
  if (isGeneratingOrLoading) return 88.0;
  return 0.0;
}

/// Column count for the behold grid: 1, 2, or 3 columns by slot count.
int _beholdGridColumnCount(int totalSlots) {
  if (totalSlots <= 1) return 1;
  if (totalSlots == 2) return 2;
  return 3;
}

class PhotoGenerateScreen extends StatefulWidget {
  const PhotoGenerateScreen({super.key});

  @override
  State<PhotoGenerateScreen> createState() => _PhotoGenerateScreenState();
}

class _PhotoGenerateScreenState extends State<PhotoGenerateScreen> {
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

  void _openGeneratedImagePreview(
    BuildContext context,
    GeneratedImage image,
  ) {
    final url = SecureImageUrl.withSessionId(image.imageUrl);
    if (url.isEmpty) return;
    unawaited(
      Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          opaque: false,
          barrierColor: Colors.black.withValues(alpha: 0.92),
          pageBuilder: (_, __, ___) {
            return GeneratedImagePreviewScreen(
              imageUrl: url,
              title: image.theme.name,
              subtitle: 'Generated in ${_viewModel.elapsedSeconds}s',
            );
          },
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
              child: child,
            );
          },
        ),
      ),
    );
  }

  /// Portrait-friendly slot for single results; 3:2 grid for multiple print styles.
  double _beholdCardAspectRatio(BuildContext context, int slotCount) {
    if (slotCount <= 1) {
      return AppConstants.themeCardSlotAspectRatio(context);
    }
    return 3 / 2;
  }

  /// Sizes the BEHOLD hero like CAPTURE: fill the available slot, then clamp to screen fractions.
  ({double width, double height}) _computeBeholdHeroCardSize(
    BuildContext context, {
    required double maxWidth,
    required double maxHeight,
    required double aspect,
  }) {
    final media = MediaQuery.sizeOf(context);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final isPhonePortrait = !isLandscape &&
        media.shortestSide < AppConstants.kTabletBreakpoint;

    final widthCapFrac = isLandscape
        ? AppConstants.kBeholdResultCardMaxWidthFractionLandscape
        : AppConstants.kCapturePreviewCardMaxWidthFractionPortrait;
    final heightCapFrac = isLandscape
        ? AppConstants.kBeholdResultCardMaxHeightFractionLandscape
        : (isPhonePortrait
            ? AppConstants.kCapturePreviewCardMaxHeightFractionPhonePortrait
            : AppConstants.kCapturePreviewCardMaxHeightFractionPortrait);

    final capW = math.min(maxWidth, media.width * widthCapFrac);
    final capH = math.min(maxHeight, media.height * heightCapFrac);

    late double cardW;
    late double cardH;
    if (capW / capH > aspect) {
      cardH = capH;
      cardW = cardH * aspect;
    } else {
      cardW = capW;
      cardH = cardW / aspect;
    }
    return (width: cardW, height: cardH);
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
    final statusLabel = _funnelSlotStatusLabel(slot);
    final borderColor = _funnelSlotBorderColor(slot, selected);
    final borderW = _funnelSlotBorderWidth(slot, selected);

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
                  final contentH = slot.maxHeight.isFinite && slot.maxHeight > 0
                      ? slot.maxHeight
                      : viewportHeight;
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: slot.maxHeight),
                      child: Align(
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: contentW,
                          child: _buildPhotosDisplay(
                            context,
                            viewModel,
                            appColors,
                            isLandscape,
                            contentW,
                            contentH,
                            true,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (hasFooter)
              Center(
                child: _buildPhotosActionFooter(
                  context,
                  viewModel,
                  appColors,
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

    final bool isGenerating = viewModel.isGenerating && viewModel.generatedImages.isEmpty;
    final bool isLoadingMore = viewModel.isLoadingMore;
    final bool isGeneratingOrLoading = isGenerating || isLoadingMore;

    final double vh = viewportHeight ?? MediaQuery.sizeOf(context).height;
    // Reduce reserved space so the photo canvas gets more prominence.
    const double reservedAboveRow = 72.0;
    final double reservedBelowRow = fixedFooterOutside ? 24.0 : 172.0;
    // When the action footer is laid out below this column, titles and status
    // ("Your masterpiece is ready", elapsed time, etc.) still sit above the hero
    // card inside the same Expanded slot. Reserve vertical budget for them so the
    // Column does not overflow short viewports (kiosk / embedded browser).
    final bool hasImages = viewModel.generatedImages.isNotEmpty;
    final double interiorChromeAboveCard = _interiorChromeAboveCardHeight(
      fixedFooterOutside: fixedFooterOutside,
      viewportHeight: viewportHeight,
      hasImages: hasImages,
      isGeneratingOrLoading: isGeneratingOrLoading,
    );
    final bool singleResultReady =
        hasImages && !isGeneratingOrLoading && viewModel.generatedImages.length <= 1;

    final layout = _GeneratedOnlyLayoutLayout(
      screenWidth: screenWidth,
      maxRowHeight: _computeBeholdMaxRowHeight(
        fixedFooterOutside: fixedFooterOutside,
        singleResultReady: singleResultReady,
        viewportHeight: vh,
        interiorChromeAboveCard: interiorChromeAboveCard,
        isLandscape: isLandscape,
        reservedAboveRow: reservedAboveRow,
        reservedBelowRow: reservedBelowRow,
      ),
      gap: cardGap,
      isGeneratingOrLoading: isGeneratingOrLoading,
      fixedFooterOutside: fixedFooterOutside,
    );
    return _buildGeneratedOnlyLayout(context, viewModel, appColors, layout);
  }

  Widget _buildGeneratedOnlyLayout(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
    _GeneratedOnlyLayoutLayout layout,
  ) {
    final screenWidth = layout.screenWidth;
    final maxRowHeight = layout.maxRowHeight;
    final gap = layout.gap;
    final isGeneratingOrLoading = layout.isGeneratingOrLoading;
    final fixedFooterOutside = layout.fixedFooterOutside;
    final isGenerating = viewModel.isGenerating && viewModel.generatedImages.isEmpty;
    final isLoadingMore = viewModel.isLoadingMore;
    final images = viewModel.generatedImages;
    final hasImages = images.isNotEmpty;
    final hideCompactHeader = viewModel.useProgressiveGenerationLayoutForSession &&
        isGeneratingOrLoading;

    final int baseSlotCount = _beholdBaseSlotCount(
      hasImages: hasImages,
      imageCount: images.length,
      isGenerating: isGenerating,
      liveSlotCount: viewModel.liveSlotCount,
    );
    final totalSlots = baseSlotCount + (isLoadingMore ? 1 : 0);
    final aspect = _beholdCardAspectRatio(context, totalSlots);

    // When we only have a single slot (initial placeholder or one image),
    // size it like the POSE capture card so the "main image placeholder" feels consistent.
    if (totalSlots == 1) {
      final size = _computeBeholdHeroCardSize(
        context,
        maxWidth: screenWidth,
        maxHeight: maxRowHeight,
        aspect: aspect,
      );
      final cardW = size.width;
      final cardH = size.height;

      final slots = _buildTransformedSlotWidgets(
        context,
        viewModel,
        appColors,
        cardW,
        cardH,
      );

      final isGenerating = viewModel.isGenerating && viewModel.generatedImages.isEmpty;
      final isLoadingMore = viewModel.isLoadingMore;
      final message = _beholdHeroMessage(
        isGeneratingOrLoading: isGeneratingOrLoading,
        isLoadingMore: isLoadingMore,
        hasImages: hasImages,
      );

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
                width: cardW,
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
    int cols = _beholdGridColumnCount(totalSlots);
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

    final slots = _buildTransformedSlotWidgets(
      context,
      viewModel,
      appColors,
      scaledW,
      scaledH,
    );

    final message = _beholdHeroMessage(
      isGeneratingOrLoading: isGeneratingOrLoading,
      isLoadingMore: isLoadingMore,
      hasImages: hasImages,
    );

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
          SizedBox(
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
    bool selected = false,
  }) {
    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 8,
        shadowColor: Colors.black.withValues(alpha: 0.38),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected
                ? CupertinoColors.systemBlue.withValues(alpha: 0.85)
                : const Color(0xFF4A4A4A),
            width: selected ? 2.0 : 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }

  /// Fills the hero card like CAPTURE / generation progress (cover, no letterbox mat).
  Widget _buildGeneratedHeroNetworkImage(
    BuildContext context, {
    required String imageUrl,
    required double width,
    required double height,
  }) {
    final secureUrl = SecureImageUrl.withSessionId(imageUrl);
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
    if (secureUrl.isEmpty) {
      return loading;
    }
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: Colors.black,
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.center,
          child: CachedNetworkImage(
            imageUrl: secureUrl,
            fit: BoxFit.contain,
            cacheWidth: cacheW,
            filterQuality: FilterQuality.medium,
            placeholder: loading,
            errorWidget: SizedBox(
              width: width,
              height: height,
              child: const Center(
                child: Icon(
                  CupertinoIcons.exclamationmark_triangle,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),
          ),
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
    bool showRemoveButton = false,
  }) {
    return SizedBox(
      width: cardWidth,
      height: cardHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openGeneratedImagePreview(context, image),
          child: _transformedSlotFrame(
            cardWidth: cardWidth,
            cardHeight: cardHeight,
            selected: image.isSelected,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                _buildGeneratedHeroNetworkImage(
                  context,
                  imageUrl: image.imageUrl,
                  width: cardWidth,
                  height: cardHeight,
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
                  left: 10,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => _openGeneratedImagePreview(context, image),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          CupertinoIcons.fullscreen,
                          size: 16,
                          color: Colors.white,
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
    final message = _transformedLoadingMessage(viewModel);
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
      bottomAccessory =
          PostRevealPolishingOverlay(steps: vm.generationRunStepPreviews);
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

