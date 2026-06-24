import 'dart:math' as math;

import 'package:flutter/cupertino.dart'
    show CupertinoButton, CupertinoColors, CupertinoSlidingSegmentedControl;
import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../../utils/print_orientation.dart';
import '../../utils/secure_image_url.dart';
import '../../utils/transformation_step_display.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/cached_network_image.dart';
import '../../views/widgets/delete_my_photos_action.dart';
import '../../views/widgets/contact_before_pay_sheet.dart';
import '../photo_capture/photo_image_from_xfile_io.dart'
    if (dart.library.html) '../photo_capture/photo_image_from_xfile_web.dart'
    as photo_image;
import '../theme_selection/theme_model.dart';
import '../transformation_details/transformation_details_view.dart';
import 'photo_generate_behold_aspect.dart';
import 'photo_generate_viewmodel.dart';

/// Layout inputs for [buildGeneratedOnlyLayout] (Sonar S107).
class GeneratedOnlyLayoutLayout {
  const GeneratedOnlyLayoutLayout({
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

typedef PhotoGeneratePhotosDisplayBuilder = Widget Function(
  BuildContext context,
  PhotoGenerateViewModel viewModel,
  AppColors appColors,
  bool isLandscape,
  double? availableWidth,
  double? viewportHeight,
  bool fixedFooterOutside,
);

typedef PhotoGeneratePhotosActionFooterBuilder = Widget Function(
  BuildContext context,
  PhotoGenerateViewModel viewModel,
  AppColors appColors,
);

typedef BeholdSlotWidgetsBuilder = List<Widget> Function(
  BuildContext context,
  PhotoGenerateViewModel viewModel,
  AppColors appColors,
  double cardWidth,
  double cardHeight,
);

typedef BeholdSimpleWidgetBuilder = Widget Function(
  BuildContext context,
  PhotoGenerateViewModel viewModel,
);

typedef BeholdHeroCardBuilder = Widget Function(
  BuildContext context,
  PhotoGenerateViewModel viewModel, {
  required double width,
  required double height,
});

/// Inputs for [buildPhotoGenerateMainContent] (Sonar S107).
class PhotoGenerateMainContentInput {
  const PhotoGenerateMainContentInput({
    required this.contentKey,
    required this.viewModel,
    required this.appColors,
    required this.isLandscape,
    this.viewportHeight,
    this.viewportWidth,
    required this.buildPhotosDisplay,
    required this.buildPhotosActionFooter,
  });

  final GlobalKey contentKey;
  final PhotoGenerateViewModel viewModel;
  final AppColors appColors;
  final bool isLandscape;
  final double? viewportHeight;
  final double? viewportWidth;
  final PhotoGeneratePhotosDisplayBuilder buildPhotosDisplay;
  final PhotoGeneratePhotosActionFooterBuilder buildPhotosActionFooter;
}

/// Builder callbacks for generated-only layouts (Sonar S107).
class GeneratedOnlyLayoutBuilders {
  const GeneratedOnlyLayoutBuilders({
    required this.beholdCardAspectRatio,
    required this.buildTransformedSlotWidgets,
    required this.buildProgressivePipelineSection,
    required this.buildLiveGenerationHeader,
    required this.buildGenerationProgressHeroCard,
    required this.buildGenerationStoryCard,
    required this.buildPhotosActionFooter,
  });

  final double Function(BuildContext context, int slotCount) beholdCardAspectRatio;
  final BeholdSlotWidgetsBuilder buildTransformedSlotWidgets;
  final BeholdSimpleWidgetBuilder buildProgressivePipelineSection;
  final BeholdSimpleWidgetBuilder buildLiveGenerationHeader;
  final BeholdHeroCardBuilder buildGenerationProgressHeroCard;
  final BeholdSimpleWidgetBuilder buildGenerationStoryCard;
  final PhotoGeneratePhotosActionFooterBuilder buildPhotosActionFooter;
}

/// Single-slot behold layout state (Sonar S107).
class GeneratedOnlySingleSlotState {
  const GeneratedOnlySingleSlotState({
    required this.screenWidth,
    required this.maxRowHeight,
    required this.aspect,
    required this.isGeneratingOrLoading,
    required this.isGenerating,
    required this.isLoadingMore,
    required this.hasImages,
    required this.hideCompactHeader,
    required this.fixedFooterOutside,
  });

  final double screenWidth;
  final double maxRowHeight;
  final double aspect;
  final bool isGeneratingOrLoading;
  final bool isGenerating;
  final bool isLoadingMore;
  final bool hasImages;
  final bool hideCompactHeader;
  final bool fixedFooterOutside;
}

/// Multi-slot behold grid state (Sonar S107).
class GeneratedOnlyGridSlotState {
  const GeneratedOnlyGridSlotState({
    required this.layout,
    required this.totalSlots,
    required this.aspect,
    required this.isGeneratingOrLoading,
    required this.isGenerating,
    required this.isLoadingMore,
    required this.hasImages,
    required this.hideCompactHeader,
  });

  final GeneratedOnlyLayoutLayout layout;
  final int totalSlots;
  final double aspect;
  final bool isGeneratingOrLoading;
  final bool isGenerating;
  final bool isLoadingMore;
  final bool hasImages;
  final bool hideCompactHeader;
}

double beholdPortraitHeightCapFraction({
  required bool isLandscape,
  required bool isPhonePortrait,
}) {
  if (isLandscape) {
    return AppConstants.kBeholdResultCardMaxHeightFractionLandscape;
  }
  if (isPhonePortrait) {
    return AppConstants.kCapturePreviewCardMaxHeightFractionPhonePortrait;
  }
  return AppConstants.kCapturePreviewCardMaxHeightFractionPortrait;
}

/// Sizes the BEHOLD hero like CAPTURE: fill the available slot, then clamp to screen fractions.
({double width, double height}) computeBeholdHeroCardSize(
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
  final heightCapFrac = beholdPortraitHeightCapFraction(
    isLandscape: isLandscape,
    isPhonePortrait: isPhonePortrait,
  );

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

Widget? generatingHeroUnderlay(PhotoGenerateViewModel vm) {
  final id = vm.selectedHeroStampId;
  if (id == null) return null;
  if (id == 'source') return _heroUnderlaySource(vm);
  if (id.startsWith('stage:')) {
    return _heroUnderlayStage(vm, id.substring(6));
  }
  if (id.startsWith('live:')) {
    return _heroUnderlayLive(vm, id.substring(5));
  }
  if (id.startsWith('funnel:')) {
    return _heroUnderlayFunnel(vm, id.substring(7));
  }
  return null;
}

Widget? _heroUnderlaySource(PhotoGenerateViewModel vm) {
  if (vm.originalPhoto == null) return null;
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

Widget? _heroUnderlayStage(PhotoGenerateViewModel vm, String key) {
  for (final s in vm.progressivePipelineStages) {
    if (s.stepKey != key) continue;
    final url = s.previewImageUrl;
    if (url == null || url.isEmpty) return null;
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
  return null;
}

Widget? _heroUnderlayLive(PhotoGenerateViewModel vm, String indexPart) {
  final idx = int.tryParse(indexPart);
  if (idx == null || idx < 0 || idx >= vm.liveSlots.length) return null;
  final slot = vm.liveSlots[idx];
  if (slot.loading) return null;
  final url = slot.imageUrl;
  if (url == null || url.isEmpty) return null;
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

Widget? _heroUnderlayFunnel(PhotoGenerateViewModel vm, String indexPart) {
  final idx = int.tryParse(indexPart);
  if (idx == null || idx < 0 || idx >= vm.pipelineFunnelSlots.length) {
    return null;
  }
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
  return null;
}

Widget buildPhotoGenerateMainContent({
  required BuildContext context,
  required PhotoGenerateMainContentInput input,
}) {
  final padding = input.isLandscape ? 12.0 : 16.0;
  final maxWidth = input.viewportWidth != null && input.viewportWidth!.isFinite
      ? input.viewportWidth!
      : double.infinity;

  if (input.viewportHeight != null && input.viewportHeight! > 0) {
    return _buildPhotoGenerateViewportColumn(
      context: context,
      input: input,
      padding: padding,
      maxWidth: maxWidth,
    );
  }

  return _buildPhotoGenerateScrollMain(
    context: context,
    input: input,
    padding: padding,
    maxWidth: maxWidth,
  );
}

Widget _buildPhotoGenerateScrollMain({
  required BuildContext context,
  required PhotoGenerateMainContentInput input,
  required double padding,
  required double maxWidth,
}) {
  return SingleChildScrollView(
    padding: EdgeInsets.all(padding),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final w =
            constraints.maxWidth.isFinite ? constraints.maxWidth : maxWidth;
        return _buildPhotoGenerateCenteredRow(
          context: context,
          input: input,
          width: w,
          fixedFooterOutside: false,
        );
      },
    ),
  );
}

Widget _buildPhotoGenerateCenteredRow({
  required BuildContext context,
  required PhotoGenerateMainContentInput input,
  required double width,
  required bool fixedFooterOutside,
  double? contentHeight,
}) {
  final contentWidth = width.isFinite ? width : null;
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: Column(
          key: input.contentKey,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            input.buildPhotosDisplay(
              context,
              input.viewModel,
              input.appColors,
              input.isLandscape,
              contentWidth,
              contentHeight ?? input.viewportHeight,
              fixedFooterOutside,
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _buildPhotoGenerateViewportColumn({
  required BuildContext context,
  required PhotoGenerateMainContentInput input,
  required double padding,
  required double maxWidth,
}) {
  final hasFooter = input.viewModel.generatedImages.isNotEmpty ||
      input.viewModel.isGenerating;

  return Padding(
    padding: EdgeInsets.all(padding),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, slot) {
              return _buildPhotoGenerateViewportScrollSlot(
                context: context,
                input: input,
                slot: slot,
                maxWidth: maxWidth,
              );
            },
          ),
        ),
        if (hasFooter)
          Center(
            child: input.buildPhotosActionFooter(
              context,
              input.viewModel,
              input.appColors,
            ),
          ),
      ],
    ),
  );
}

Widget _buildPhotoGenerateViewportScrollSlot({
  required BuildContext context,
  required PhotoGenerateMainContentInput input,
  required BoxConstraints slot,
  required double maxWidth,
}) {
  final w = slot.maxWidth.isFinite && slot.maxWidth > 0
      ? slot.maxWidth
      : maxWidth;
  final contentW = w.isFinite ? w : null;
  final contentH = slot.maxHeight.isFinite && slot.maxHeight > 0
      ? slot.maxHeight
      : input.viewportHeight;
  return SingleChildScrollView(
    physics: const ClampingScrollPhysics(),
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: slot.maxHeight),
      child: Align(
        alignment: Alignment.center,
        child: SizedBox(
          width: contentW,
          child: input.buildPhotosDisplay(
            context,
            input.viewModel,
            input.appColors,
            input.isLandscape,
            contentW,
            contentH,
            true,
          ),
        ),
      ),
    ),
  );
}

Widget buildPhotosActionFooter({
  required BuildContext context,
  required PhotoGenerateViewModel viewModel,
  required bool paymentsEnabled,
  required bool isMounted,
  required void Function(ThemeModel theme) onAddStyleSelected,
}) {
  final canAddMoreStyle = viewModel.canShowAddAnotherStyleButton;
  final isGenerating =
      viewModel.isGenerating && viewModel.generatedImages.isEmpty;
  final isLoadingMore = viewModel.isLoadingMore;
  final isGeneratingOrLoading = isGenerating || isLoadingMore;

  return SizedBox(
    width: 360,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isGeneratingOrLoading && viewModel.generatedImages.isNotEmpty)
          _buildPrintOrientationToggle(viewModel: viewModel),
        if (!isGeneratingOrLoading && viewModel.generatedImages.isNotEmpty)
          const SizedBox(height: 12),
        _buildContinueButton(
          context: context,
          viewModel: viewModel,
          paymentsEnabled: paymentsEnabled,
          isGeneratingOrLoading: isGeneratingOrLoading,
        ),
        if (!isGeneratingOrLoading &&
            viewModel.lastTransformationRunId != null &&
            viewModel.generatedImages.isNotEmpty)
          _buildTransformationDetailsLink(context, viewModel),
        if (paymentsEnabled && viewModel.selectedCount > 0)
          _buildSelectedTotalLine(viewModel),
        if (canAddMoreStyle)
          _buildAddAnotherStyleButton(
            context: context,
            viewModel: viewModel,
            isMounted: isMounted,
            onAddStyleSelected: onAddStyleSelected,
          ),
        if (!isGeneratingOrLoading && viewModel.generatedImages.isNotEmpty)
          DeleteMyPhotosButton(
            compact: true,
            onBeforeDelete: () async {
              viewModel.cancelOperation();
            },
          ),
      ],
    ),
  );
}

Widget _buildPrintOrientationToggle({
  required PhotoGenerateViewModel viewModel,
}) {
  final personHint = viewModel.sessionPersonCount;
  final hintText = personHint == null
      ? 'Choose how your photo prints'
      : personHint <= 1
          ? 'Solo photo — portrait suggested'
          : 'Group of $personHint — landscape suggested';

  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Print orientation',
        style: TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 4),
      Text(
        hintText,
        style: const TextStyle(color: Colors.white70, fontSize: 11),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 10),
      CupertinoSlidingSegmentedControl<PrintOrientation>(
        groupValue: viewModel.printOrientation,
        backgroundColor: Colors.black.withValues(alpha: 0.35),
        thumbColor: CupertinoColors.systemBlue,
        children: {
          for (final orientation in PrintOrientation.values)
            orientation: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                orientation.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        },
        onValueChanged: (value) {
          if (value != null) viewModel.setPrintOrientation(value);
        },
      ),
    ],
  );
}

Widget _buildContinueButton({
  required BuildContext context,
  required PhotoGenerateViewModel viewModel,
  required bool paymentsEnabled,
  required bool isGeneratingOrLoading,
}) {
  final canContinue =
      !isGeneratingOrLoading && viewModel.hasSelectedImages;
  return CupertinoButton(
    padding: const EdgeInsets.symmetric(vertical: 16),
    color: canContinue
        ? CupertinoColors.systemBlue
        : CupertinoColors.systemGrey,
    borderRadius: BorderRadius.circular(12),
    onPressed: canContinue
        ? () => _onPhotoGenerateContinuePressed(
              context: context,
              viewModel: viewModel,
              paymentsEnabled: paymentsEnabled,
            )
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
  );
}

Future<void> _onPhotoGenerateContinuePressed({
  required BuildContext context,
  required PhotoGenerateViewModel viewModel,
  required bool paymentsEnabled,
}) async {
  final selectedImages = viewModel.selectedGeneratedImages;
  if (selectedImages.isEmpty) return;

  final contact = await _photoGenerateContactBeforePay(
    context: context,
    paymentsEnabled: paymentsEnabled,
  );
  if (!context.mounted) return;
  if (paymentsEnabled && contact == null) return;

  await viewModel.syncPrintOrientationBeforeCheckout();

  if (!context.mounted) return;

  await Navigator.pushNamed(
    context,
    AppConstants.kRouteResult,
    arguments: {
      'generatedImages': selectedImages,
      'originalPhoto': viewModel.originalPhoto,
      'printOrientation': viewModel.printOrientation.apiValue,
      'customerName': contact?.customerName ?? '',
      'customerPhone': contact?.customerPhone ?? '',
      'customerWhatsappOptIn': contact?.whatsappOptIn ?? false,
    },
  );
}

Future<ContactBeforePayResult?> _photoGenerateContactBeforePay({
  required BuildContext context,
  required bool paymentsEnabled,
}) async {
  if (!paymentsEnabled) return null;
  return showContactBeforePaySheet(context);
}

Widget _buildTransformationDetailsLink(
  BuildContext context,
  PhotoGenerateViewModel viewModel,
) {
  return TextButton(
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
  );
}

Widget _buildSelectedTotalLine(PhotoGenerateViewModel viewModel) {
  final extra = viewModel.selectedCount > 1
      ? '  (+₹${(viewModel.selectedCount - 1) * viewModel.additionalPrintPrice})'
      : '';
  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Center(
      child: Text(
        'Total: ₹${viewModel.selectedTotalPrice}$extra',
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.78),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

Widget _buildAddAnotherStyleButton({
  required BuildContext context,
  required PhotoGenerateViewModel viewModel,
  required bool isMounted,
  required void Function(ThemeModel theme) onAddStyleSelected,
}) {
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Center(
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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
                      viewModel.generatedImages.map((e) => e.theme.id),
                    ),
                  },
                );
                if (!isMounted) return;
                if (result is ThemeModel) {
                  onAddStyleSelected(result);
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
  );
}

Widget buildGeneratedOnlyLayout({
  required BuildContext context,
  required PhotoGenerateViewModel viewModel,
  required AppColors appColors,
  required GeneratedOnlyLayoutLayout layout,
  required GeneratedOnlyLayoutBuilders builders,
}) {
  final screenWidth = layout.screenWidth;
  final maxRowHeight = layout.maxRowHeight;
  final isGeneratingOrLoading = layout.isGeneratingOrLoading;
  final fixedFooterOutside = layout.fixedFooterOutside;
  final isGenerating =
      viewModel.isGenerating && viewModel.generatedImages.isEmpty;
  final isLoadingMore = viewModel.isLoadingMore;
  final images = viewModel.generatedImages;
  final hasImages = images.isNotEmpty;
  final hideCompactHeader = viewModel.useProgressiveGenerationLayoutForSession &&
      isGeneratingOrLoading;

  final baseSlotCount = beholdBaseSlotCount(
    hasImages: hasImages,
    imageCount: images.length,
    isGenerating: isGenerating,
    liveSlotCount: viewModel.liveSlotCount,
  );
  final totalSlots = baseSlotCount + (isLoadingMore ? 1 : 0);
  final aspect = totalSlots <= 1
      ? beholdSingleResultCardAspectRatio(
          context,
          viewModel,
          maxWidth: screenWidth,
          maxHeight: maxRowHeight,
        )
      : builders.beholdCardAspectRatio(context, totalSlots);

  if (totalSlots == 1) {
    return _buildGeneratedOnlySingleSlotLayout(
      context: context,
      viewModel: viewModel,
      appColors: appColors,
      slot: GeneratedOnlySingleSlotState(
        screenWidth: screenWidth,
        maxRowHeight: maxRowHeight,
        aspect: aspect,
        isGeneratingOrLoading: isGeneratingOrLoading,
        isGenerating: isGenerating,
        isLoadingMore: isLoadingMore,
        hasImages: hasImages,
        hideCompactHeader: hideCompactHeader,
        fixedFooterOutside: fixedFooterOutside,
      ),
      builders: builders,
    );
  }

  return _buildGeneratedOnlyGridLayout(
    context: context,
    viewModel: viewModel,
    appColors: appColors,
    slot: GeneratedOnlyGridSlotState(
      layout: layout,
      totalSlots: totalSlots,
      aspect: aspect,
      isGeneratingOrLoading: isGeneratingOrLoading,
      isGenerating: isGenerating,
      isLoadingMore: isLoadingMore,
      hasImages: hasImages,
      hideCompactHeader: hideCompactHeader,
    ),
    builders: builders,
  );
}

String beholdHeroMessage({
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

int beholdBaseSlotCount({
  required bool hasImages,
  required int imageCount,
  required bool isGenerating,
  required int liveSlotCount,
}) {
  if (hasImages) return imageCount;
  if (isGenerating && liveSlotCount > 0) return liveSlotCount;
  return 1;
}

int beholdGridColumnCount(int totalSlots) {
  if (totalSlots <= 1) return 1;
  if (totalSlots == 2) return 2;
  return 3;
}

Widget _buildBeholdLayoutHeader({
  required BuildContext context,
  required PhotoGenerateViewModel viewModel,
  required bool hideCompactHeader,
  required bool isGeneratingOrLoading,
  required bool isGenerating,
  required BeholdSimpleWidgetBuilder buildProgressivePipelineSection,
  required BeholdSimpleWidgetBuilder buildLiveGenerationHeader,
}) {
  if (hideCompactHeader &&
      isGeneratingOrLoading &&
      !viewModel.showProgressStampStrip) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        buildProgressivePipelineSection(context, viewModel),
        const SizedBox(height: 12),
      ],
    );
  }
  if (!hideCompactHeader && isGenerating && viewModel.liveSlotCount > 0) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        buildLiveGenerationHeader(context, viewModel),
        const SizedBox(height: 12),
      ],
    );
  }
  return const SizedBox.shrink();
}

Widget _buildBeholdHeroMessageBlock({
  required String message,
  required bool hasImages,
  required bool isGeneratingOrLoading,
  required PhotoGenerateViewModel viewModel,
  required bool showElapsed,
}) {
  if (message.isEmpty) return const SizedBox.shrink();
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
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
      if (showElapsed && hasImages && !isGeneratingOrLoading) ...[
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
  );
}

Widget _buildGeneratedOnlySingleSlotLayout({
  required BuildContext context,
  required PhotoGenerateViewModel viewModel,
  required AppColors appColors,
  required GeneratedOnlySingleSlotState slot,
  required GeneratedOnlyLayoutBuilders builders,
}) {
  final size = computeBeholdHeroCardSize(
    context,
    maxWidth: slot.screenWidth,
    maxHeight: slot.maxRowHeight,
    aspect: slot.aspect,
  );
  final cardW = size.width;
  final cardH = size.height;
  final slots = builders.buildTransformedSlotWidgets(
    context,
    viewModel,
    appColors,
    cardW,
    cardH,
  );
  final message = beholdHeroMessage(
    isGeneratingOrLoading: slot.isGeneratingOrLoading,
    isLoadingMore: slot.isLoadingMore,
    hasImages: slot.hasImages,
  );

  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBeholdLayoutHeader(
          context: context,
          viewModel: viewModel,
          hideCompactHeader: slot.hideCompactHeader,
          isGeneratingOrLoading: slot.isGeneratingOrLoading,
          isGenerating: slot.isGenerating,
          buildProgressivePipelineSection:
              builders.buildProgressivePipelineSection,
          buildLiveGenerationHeader: builders.buildLiveGenerationHeader,
        ),
        _buildBeholdHeroMessageBlock(
          message: message,
          hasImages: slot.hasImages,
          isGeneratingOrLoading: slot.isGeneratingOrLoading,
          viewModel: viewModel,
          showElapsed: true,
        ),
        _buildGeneratedOnlySingleSlotHero(
          context: context,
          viewModel: viewModel,
          slot: slot,
          cardW: cardW,
          cardH: cardH,
          slots: slots,
          builders: builders,
        ),
        if ((slot.hasImages ||
                slot.isGenerating ||
                slot.isLoadingMore) &&
            !slot.fixedFooterOutside) ...[
          const SizedBox(height: 18),
          builders.buildPhotosActionFooter(context, viewModel, appColors),
        ],
      ],
    ),
  );
}

Widget _buildGeneratedOnlySingleSlotHero({
  required BuildContext context,
  required PhotoGenerateViewModel viewModel,
  required GeneratedOnlySingleSlotState slot,
  required double cardW,
  required double cardH,
  required List<Widget> slots,
  required GeneratedOnlyLayoutBuilders builders,
}) {
  if (slot.isGeneratingOrLoading && !slot.hasImages) {
    return builders.buildGenerationProgressHeroCard(
      context,
      viewModel,
      width: cardW,
      height: cardH,
    );
  }
  final wideStoryLayout = MediaQuery.sizeOf(context).width >= 980;
  if (wideStoryLayout && slot.isGeneratingOrLoading) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Center(child: slots.first),
        const SizedBox(width: 18),
        builders.buildGenerationStoryCard(context, viewModel),
      ],
    );
  }
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Center(child: slots.first),
      if (slot.isGeneratingOrLoading) ...[
        const SizedBox(height: 18),
        builders.buildGenerationStoryCard(context, viewModel),
      ],
    ],
  );
}

Widget _buildGeneratedOnlyGridLayout({
  required BuildContext context,
  required PhotoGenerateViewModel viewModel,
  required AppColors appColors,
  required GeneratedOnlyGridSlotState slot,
  required GeneratedOnlyLayoutBuilders builders,
}) {
  final screenWidth = slot.layout.screenWidth;
  final maxRowHeight = slot.layout.maxRowHeight;
  final gap = slot.layout.gap;
  final fixedFooterOutside = slot.layout.fixedFooterOutside;

  var cols = beholdGridColumnCount(slot.totalSlots);
  cols = cols.clamp(1, 3);
  final rows = (slot.totalSlots / cols).ceil().clamp(1, 3);

  final gridH = maxRowHeight;
  final cardH = (gridH - gap * (rows - 1)) / rows;
  final cardW = cardH * slot.aspect;
  final gridW = cols * cardW + gap * (cols - 1);
  final scale =
      gridW > screenWidth ? (screenWidth / gridW).clamp(0.35, 1.0) : 1.0;
  final scaledW = cardW * scale;
  final scaledH = cardH * scale;

  final slots = builders.buildTransformedSlotWidgets(
    context,
    viewModel,
    appColors,
    scaledW,
    scaledH,
  );
  final message = beholdHeroMessage(
    isGeneratingOrLoading: slot.isGeneratingOrLoading,
    isLoadingMore: slot.isLoadingMore,
    hasImages: slot.hasImages,
  );

  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBeholdLayoutHeader(
          context: context,
          viewModel: viewModel,
          hideCompactHeader: slot.hideCompactHeader,
          isGeneratingOrLoading: slot.isGeneratingOrLoading,
          isGenerating: slot.isGenerating,
          buildProgressivePipelineSection:
              builders.buildProgressivePipelineSection,
          buildLiveGenerationHeader: builders.buildLiveGenerationHeader,
        ),
        _buildBeholdHeroMessageBlock(
          message: message,
          hasImages: slot.hasImages,
          isGeneratingOrLoading: slot.isGeneratingOrLoading,
          viewModel: viewModel,
          showElapsed: false,
        ),
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
        if ((slot.hasImages || slot.isGenerating || slot.isLoadingMore) &&
            !fixedFooterOutside) ...[
          const SizedBox(height: 18),
          builders.buildPhotosActionFooter(context, viewModel, appColors),
        ],
      ],
    ),
  );
}
