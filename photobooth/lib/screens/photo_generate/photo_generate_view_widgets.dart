import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoColors;
import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../../utils/secure_image_url.dart';
import '../../utils/transformation_step_display.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/cached_network_image.dart';
import '../../views/widgets/contact_before_pay_sheet.dart';
import '../photo_capture/photo_image_from_xfile_io.dart'
    if (dart.library.html) '../photo_capture/photo_image_from_xfile_web.dart'
    as photo_image;
import '../theme_selection/theme_model.dart';
import '../transformation_details/transformation_details_view.dart';
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

typedef PhotoGeneratePhotosDisplayBuilder = Widget Function(
  BuildContext context,
  PhotoGenerateViewModel viewModel,
  AppColors appColors,
  bool isLandscape,
  double? availableWidth,
  double? viewportHeight,
  bool fixedFooterOutside,
);

Widget buildPhotoGenerateMainContent({
  required BuildContext context,
  required GlobalKey contentKey,
  required PhotoGenerateViewModel viewModel,
  required AppColors appColors,
  required bool isLandscape,
  required double? viewportHeight,
  required double? viewportWidth,
  required PhotoGeneratePhotosDisplayBuilder buildPhotosDisplay,
  required Widget Function(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
  ) buildPhotosActionFooter,
}) {
  final padding = isLandscape ? 12.0 : 16.0;
  final maxWidth = viewportWidth != null && viewportWidth.isFinite
      ? viewportWidth
      : double.infinity;

  Widget buildContent(double width) {
    final contentWidth = width.isFinite ? width : null;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width),
          child: Column(
            key: contentKey,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildPhotosDisplay(
                context,
                viewModel,
                appColors,
                isLandscape,
                contentWidth,
                viewportHeight,
                false,
              ),
            ],
          ),
        ),
      ],
    );
  }

  if (viewportHeight != null && viewportHeight > 0) {
    final hasFooter =
        viewModel.generatedImages.isNotEmpty || viewModel.isGenerating;

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
                final contentH =
                    slot.maxHeight.isFinite && slot.maxHeight > 0
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
                        child: buildPhotosDisplay(
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
              child: buildPhotosActionFooter(context, viewModel, appColors),
            ),
        ],
      ),
    );
  }

  return SingleChildScrollView(
    padding: EdgeInsets.all(padding),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final w =
            constraints.maxWidth.isFinite ? constraints.maxWidth : maxWidth;
        return buildContent(w);
      },
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
    width: 320,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
      ],
    ),
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
        ? () async {
            final selectedImages = viewModel.selectedGeneratedImages;
            if (selectedImages.isEmpty) return;

            final routerContext = context;
            var customerName = '';
            var customerPhone = '';
            var customerWhatsappOptIn = false;
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
  );
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

Widget buildGeneratedOnlyLayout({
  required BuildContext context,
  required PhotoGenerateViewModel viewModel,
  required AppColors appColors,
  required GeneratedOnlyLayoutLayout layout,
  required double Function(BuildContext context, int slotCount) beholdCardAspectRatio,
  required BeholdSlotWidgetsBuilder buildTransformedSlotWidgets,
  required BeholdSimpleWidgetBuilder buildProgressivePipelineSection,
  required BeholdSimpleWidgetBuilder buildLiveGenerationHeader,
  required BeholdHeroCardBuilder buildGenerationProgressHeroCard,
  required BeholdSimpleWidgetBuilder buildGenerationStoryCard,
  required Widget Function(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
  ) buildPhotosActionFooter,
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
  final aspect = beholdCardAspectRatio(context, totalSlots);

  if (totalSlots == 1) {
    return _buildGeneratedOnlySingleSlotLayout(
      context: context,
      viewModel: viewModel,
      appColors: appColors,
      screenWidth: screenWidth,
      maxRowHeight: maxRowHeight,
      aspect: aspect,
      isGeneratingOrLoading: isGeneratingOrLoading,
      isGenerating: isGenerating,
      isLoadingMore: isLoadingMore,
      hasImages: hasImages,
      hideCompactHeader: hideCompactHeader,
      fixedFooterOutside: fixedFooterOutside,
      buildTransformedSlotWidgets: buildTransformedSlotWidgets,
      buildProgressivePipelineSection: buildProgressivePipelineSection,
      buildLiveGenerationHeader: buildLiveGenerationHeader,
      buildGenerationProgressHeroCard: buildGenerationProgressHeroCard,
      buildGenerationStoryCard: buildGenerationStoryCard,
      buildPhotosActionFooter: buildPhotosActionFooter,
    );
  }

  return _buildGeneratedOnlyGridLayout(
    context: context,
    viewModel: viewModel,
    appColors: appColors,
    layout: layout,
    totalSlots: totalSlots,
    aspect: aspect,
    isGeneratingOrLoading: isGeneratingOrLoading,
    isGenerating: isGenerating,
    isLoadingMore: isLoadingMore,
    hasImages: hasImages,
    hideCompactHeader: hideCompactHeader,
    buildTransformedSlotWidgets: buildTransformedSlotWidgets,
    buildProgressivePipelineSection: buildProgressivePipelineSection,
    buildLiveGenerationHeader: buildLiveGenerationHeader,
    buildPhotosActionFooter: buildPhotosActionFooter,
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
  required double screenWidth,
  required double maxRowHeight,
  required double aspect,
  required bool isGeneratingOrLoading,
  required bool isGenerating,
  required bool isLoadingMore,
  required bool hasImages,
  required bool hideCompactHeader,
  required bool fixedFooterOutside,
  required BeholdSlotWidgetsBuilder buildTransformedSlotWidgets,
  required BeholdSimpleWidgetBuilder buildProgressivePipelineSection,
  required BeholdSimpleWidgetBuilder buildLiveGenerationHeader,
  required BeholdHeroCardBuilder buildGenerationProgressHeroCard,
  required BeholdSimpleWidgetBuilder buildGenerationStoryCard,
  required Widget Function(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
  ) buildPhotosActionFooter,
}) {
  final size = computeBeholdHeroCardSize(
    context,
    maxWidth: screenWidth,
    maxHeight: maxRowHeight,
    aspect: aspect,
  );
  final cardW = size.width;
  final cardH = size.height;
  final slots = buildTransformedSlotWidgets(
    context,
    viewModel,
    appColors,
    cardW,
    cardH,
  );
  final message = beholdHeroMessage(
    isGeneratingOrLoading: isGeneratingOrLoading,
    isLoadingMore: isLoadingMore,
    hasImages: hasImages,
  );
  final wideStoryLayout = MediaQuery.sizeOf(context).width >= 980;

  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBeholdLayoutHeader(
          context: context,
          viewModel: viewModel,
          hideCompactHeader: hideCompactHeader,
          isGeneratingOrLoading: isGeneratingOrLoading,
          isGenerating: isGenerating,
          buildProgressivePipelineSection: buildProgressivePipelineSection,
          buildLiveGenerationHeader: buildLiveGenerationHeader,
        ),
        _buildBeholdHeroMessageBlock(
          message: message,
          hasImages: hasImages,
          isGeneratingOrLoading: isGeneratingOrLoading,
          viewModel: viewModel,
          showElapsed: true,
        ),
        if (isGeneratingOrLoading && !hasImages)
          buildGenerationProgressHeroCard(
            context,
            viewModel,
            width: cardW,
            height: cardH,
          )
        else if (wideStoryLayout && isGeneratingOrLoading)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Center(child: slots.first),
              const SizedBox(width: 18),
              buildGenerationStoryCard(context, viewModel),
            ],
          )
        else ...[
          Center(child: slots.first),
          if (isGeneratingOrLoading) ...[
            const SizedBox(height: 18),
            buildGenerationStoryCard(context, viewModel),
          ],
        ],
        if ((hasImages || isGenerating || isLoadingMore) && !fixedFooterOutside) ...[
          const SizedBox(height: 18),
          buildPhotosActionFooter(context, viewModel, appColors),
        ],
      ],
    ),
  );
}

Widget _buildGeneratedOnlyGridLayout({
  required BuildContext context,
  required PhotoGenerateViewModel viewModel,
  required AppColors appColors,
  required GeneratedOnlyLayoutLayout layout,
  required int totalSlots,
  required double aspect,
  required bool isGeneratingOrLoading,
  required bool isGenerating,
  required bool isLoadingMore,
  required bool hasImages,
  required bool hideCompactHeader,
  required BeholdSlotWidgetsBuilder buildTransformedSlotWidgets,
  required BeholdSimpleWidgetBuilder buildProgressivePipelineSection,
  required BeholdSimpleWidgetBuilder buildLiveGenerationHeader,
  required Widget Function(
    BuildContext context,
    PhotoGenerateViewModel viewModel,
    AppColors appColors,
  ) buildPhotosActionFooter,
}) {
  final screenWidth = layout.screenWidth;
  final maxRowHeight = layout.maxRowHeight;
  final gap = layout.gap;
  final fixedFooterOutside = layout.fixedFooterOutside;

  var cols = beholdGridColumnCount(totalSlots);
  cols = cols.clamp(1, 3);
  final rows = (totalSlots / cols).ceil().clamp(1, 3);

  final gridH = maxRowHeight;
  final cardH = (gridH - gap * (rows - 1)) / rows;
  final cardW = cardH * aspect;
  final gridW = cols * cardW + gap * (cols - 1);
  final scale =
      gridW > screenWidth ? (screenWidth / gridW).clamp(0.35, 1.0) : 1.0;
  final scaledW = cardW * scale;
  final scaledH = cardH * scale;

  final slots = buildTransformedSlotWidgets(
    context,
    viewModel,
    appColors,
    scaledW,
    scaledH,
  );
  final message = beholdHeroMessage(
    isGeneratingOrLoading: isGeneratingOrLoading,
    isLoadingMore: isLoadingMore,
    hasImages: hasImages,
  );

  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBeholdLayoutHeader(
          context: context,
          viewModel: viewModel,
          hideCompactHeader: hideCompactHeader,
          isGeneratingOrLoading: isGeneratingOrLoading,
          isGenerating: isGenerating,
          buildProgressivePipelineSection: buildProgressivePipelineSection,
          buildLiveGenerationHeader: buildLiveGenerationHeader,
        ),
        _buildBeholdHeroMessageBlock(
          message: message,
          hasImages: hasImages,
          isGeneratingOrLoading: isGeneratingOrLoading,
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
        if ((hasImages || isGenerating || isLoadingMore) && !fixedFooterOutside) ...[
          const SizedBox(height: 18),
          buildPhotosActionFooter(context, viewModel, appColors),
        ],
      ],
    ),
  );
}
