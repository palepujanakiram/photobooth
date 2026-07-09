import 'dart:math' as math;

import 'package:flutter/cupertino.dart'
    show
        CupertinoButton,
        CupertinoColors,
        CupertinoIcons,
        CupertinoSlidingSegmentedControl;
import 'package:flutter/material.dart';

import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/print_orientation.dart';
import '../../utils/secure_image_url.dart';
import '../../utils/transformation_step_display.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/cached_network_image.dart';
import '../../views/widgets/delete_my_photos_action.dart';
import '../../views/widgets/contact_before_pay_sheet.dart';
import '../../services/customer_session_lifecycle.dart';
import '../photo_capture/photo_image_from_xfile_io.dart'
    if (dart.library.html) '../photo_capture/photo_image_from_xfile_web.dart'
    as photo_image;
import '../theme_selection/theme_model.dart';
import '../transformation_details/transformation_details_view.dart';
import 'behold_result_ready_widgets.dart';
import 'photo_generate_behold_aspect.dart';
import 'generation_wait_helpers.dart';
import 'generation_wait_widgets.dart';
import 'photo_generate_viewmodel.dart';

/// True when BEHOLD shows one finished result (hero-max layout applies).
bool isBeholdSingleResultReady(PhotoGenerateViewModel viewModel) {
  final isGenerating =
      viewModel.isGenerating && viewModel.generatedImages.isEmpty;
  return viewModel.generatedImages.isNotEmpty &&
      !isGenerating &&
      !viewModel.isLoadingMore &&
      viewModel.generatedImages.length <= 1;
}

/// Max width for the bottom Continue button (matches theme selection / capture).
const double kBeholdReadyContinueMaxWidth = 360;

/// Max width for orientation + secondary links under the hero.
const double kBeholdReadyControlsMaxWidth = 520;

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

/// Footer action dependencies for the BEHOLD ready split layout (Sonar S107).
class BeholdReadyActionInput {
  const BeholdReadyActionInput({
    required this.paymentsEnabled,
    required this.isMounted,
    required this.onAddStyleSelected,
  });

  final bool paymentsEnabled;
  final bool isMounted;
  final void Function(ThemeModel theme) onAddStyleSelected;
}

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
    required this.beholdReadyActions,
    required this.buildBeholdReadyHero,
  });

  final GlobalKey contentKey;
  final PhotoGenerateViewModel viewModel;
  final AppColors appColors;
  final bool isLandscape;
  final double? viewportHeight;
  final double? viewportWidth;
  final PhotoGeneratePhotosDisplayBuilder buildPhotosDisplay;
  final PhotoGeneratePhotosActionFooterBuilder buildPhotosActionFooter;
  final BeholdReadyActionInput beholdReadyActions;
  final BeholdHeroCardBuilder buildBeholdReadyHero;
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
  bool fillAvailableSlot = false,
}) {
  if (fillAvailableSlot) {
    return fitBeholdHeroAspectInBox(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      aspect: aspect,
    );
  }

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

  return fitBeholdHeroAspectInBox(
    maxWidth: capW,
    maxHeight: capH,
    aspect: aspect,
  );
}

/// Sizes the single-result BEHOLD hero for the current print orientation.
///
/// Portrait print cards grow to fill the available slot height. Landscape cards
/// are sized from width so a wide 6×4 preview does not float in a tall slot.
({double width, double height}) computeBeholdSingleResultHeroCardSize(
  BuildContext context, {
  required PhotoGenerateViewModel viewModel,
  required double maxWidth,
  required double maxHeight,
}) {
  final aspect = beholdSingleResultCardAspectRatio(
    context,
    viewModel,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
  );
  if (viewModel.printOrientation == PrintOrientation.landscape) {
    return fitBeholdHeroAspectInBox(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      aspect: aspect,
    );
  }
  return computeBeholdHeroCardSize(
    context,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    aspect: aspect,
    fillAvailableSlot: true,
  );
}

/// Builds the single-result BEHOLD hero card at explicit dimensions.
Widget buildBeholdReadyHeroWidget({
  required BuildContext context,
  required PhotoGenerateViewModel viewModel,
  required AppColors appColors,
  required double width,
  required double height,
  required BeholdSlotWidgetsBuilder buildTransformedSlotWidgets,
}) {
  final slots = buildTransformedSlotWidgets(
    context,
    viewModel,
    appColors,
    width,
    height,
  );
  if (slots.isEmpty) {
    return _beholdReadyHeroMissingPlaceholder(width: width, height: height);
  }
  return SizedBox(
    width: width,
    height: height,
    child: slots.first,
  );
}

Widget _beholdReadyHeroMissingPlaceholder({
  required double width,
  required double height,
}) {
  return SizedBox(
    width: width,
    height: height,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: const Center(
        child: Icon(
          CupertinoIcons.photo,
          color: Colors.white38,
          size: 40,
        ),
      ),
    ),
  );
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
  if (isBeholdSingleResultReady(input.viewModel)) {
    return _buildBeholdHeroMaxViewport(
      context: context,
      input: input,
      maxWidth: maxWidth,
    );
  }

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
        if (hasFooter) ...[
          const SizedBox(height: 8),
          input.buildPhotosActionFooter(
            context,
            input.viewModel,
            input.appColors,
          ),
        ],
      ],
    ),
  );
}

/// BEHOLD ready layout: hero photo, controls, bottom Continue (no scroll).
Widget buildBeholdReadyScreenLayout({
  required BuildContext context,
  required BoxConstraints constraints,
  required PhotoGenerateMainContentInput input,
}) {
  const edgePadding = 12.0;
  final actions = input.beholdReadyActions;
  final vm = input.viewModel;
  final media = MediaQuery.sizeOf(context);
  final viewportH = _beholdReadyViewportHeight(
    constraints,
    media.height,
    inputViewportHeight: input.viewportHeight,
  );
  final viewportW = _beholdReadyViewportWidth(constraints, input, media.width);
  final continueButton = _buildContinueButton(
    context: context,
    viewModel: vm,
    paymentsEnabled: actions.paymentsEnabled,
    isGeneratingOrLoading: false,
  );

  return SizedBox(
    width: viewportW,
    height: viewportH,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: edgePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (vm.printOrientation == PrintOrientation.portrait)
            Expanded(
              child: _buildBeholdReadyHeroSlot(
                input: input,
                viewModel: vm,
              ),
            )
          else
            Flexible(
              fit: FlexFit.loose,
              child: Align(
                alignment: Alignment.topCenter,
                child: _buildBeholdReadyHeroSlot(
                  input: input,
                  viewModel: vm,
                ),
              ),
            ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: kBeholdReadyControlsMaxWidth,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPrintOrientationBelowImage(viewModel: vm),
                  const SizedBox(height: 8),
                  _buildBeholdReadySecondaryLinks(
                    context: context,
                    viewModel: vm,
                    actions: actions,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: kBeholdReadyContinueMaxWidth,
              ),
              child: SizedBox(
                width: double.infinity,
                child: continueButton,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(child: BeholdReadyPrivacyFooter(compact: true)),
          const SizedBox(height: 4),
        ],
      ),
    ),
  );
}

Widget _buildBeholdReadyHeroSlot({
  required PhotoGenerateMainContentInput input,
  required PhotoGenerateViewModel viewModel,
}) {
  final isLandscapePrint =
      viewModel.printOrientation == PrintOrientation.landscape;

  return LayoutBuilder(
    builder: (context, slot) {
      final maxW = math.min(720.0, slot.maxWidth);
      final maxH = slot.maxHeight.isFinite && slot.maxHeight > 0
          ? slot.maxHeight
          : MediaQuery.sizeOf(context).height * 0.5;
      final heroSize = computeBeholdSingleResultHeroCardSize(
        context,
        viewModel: viewModel,
        maxWidth: maxW,
        maxHeight: maxH,
      );
      return Align(
        alignment:
            isLandscapePrint ? Alignment.topCenter : Alignment.center,
        child: SizedBox(
          width: heroSize.width,
          height: heroSize.height,
          child: input.buildBeholdReadyHero(
            context,
            viewModel,
            width: heroSize.width,
            height: heroSize.height,
          ),
        ),
      );
    },
  );
}

double _beholdReadyViewportHeight(
  BoxConstraints constraints,
  double screenH, {
  double? inputViewportHeight,
}) {
  if (constraints.maxHeight.isFinite && constraints.maxHeight > 0) {
    return constraints.maxHeight;
  }
  if (inputViewportHeight != null &&
      inputViewportHeight.isFinite &&
      inputViewportHeight > 0) {
    return inputViewportHeight;
  }
  return math.max(200.0, screenH * 0.5);
}

double _beholdReadyViewportWidth(
  BoxConstraints constraints,
  PhotoGenerateMainContentInput input,
  double screenW,
) {
  final fromInput = input.viewportWidth;
  if (fromInput != null && fromInput.isFinite && fromInput > 0) {
    return fromInput;
  }
  if (constraints.maxWidth.isFinite && constraints.maxWidth > 0) {
    return constraints.maxWidth;
  }
  return screenW;
}

Widget _buildBeholdHeroMaxViewport({
  required BuildContext context,
  required PhotoGenerateMainContentInput input,
  required double maxWidth,
}) {
  final h = input.viewportHeight;
  final w = input.viewportWidth ?? maxWidth;
  return buildBeholdReadyScreenLayout(
    context: context,
    constraints: BoxConstraints(
      maxWidth: w.isFinite && w > 0 ? w : maxWidth,
      maxHeight: h != null && h.isFinite && h > 0 ? h : double.infinity,
    ),
    input: input,
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
  final vm = input.viewModel;
  final readySingle = isBeholdSingleResultReady(vm);

  final display = SizedBox(
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
  );

  if (readySingle && slot.maxHeight.isFinite && slot.maxHeight > 0) {
    return SizedBox(
      height: slot.maxHeight,
      width: contentW,
      child: display,
    );
  }

  return SingleChildScrollView(
    physics: const ClampingScrollPhysics(),
    child: ConstrainedBox(
      constraints: BoxConstraints(minHeight: slot.maxHeight),
      child: Align(
        alignment: Alignment.center,
        child: display,
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
  final isReadyWithImages =
      !isGeneratingOrLoading && viewModel.generatedImages.isNotEmpty;

  if (isReadyWithImages) {
    final actions = BeholdReadyActionInput(
      paymentsEnabled: paymentsEnabled,
      isMounted: isMounted,
      onAddStyleSelected: onAddStyleSelected,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBeholdReadySecondaryStrip(
          context: context,
          viewModel: viewModel,
          actions: actions,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: _buildContinueButton(
            context: context,
            viewModel: viewModel,
            paymentsEnabled: paymentsEnabled,
            isGeneratingOrLoading: false,
          ),
        ),
      ],
    );
  }

  return SizedBox(
    width: 360,
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

Widget _buildBeholdReadySecondaryStrip({
  required BuildContext context,
  required PhotoGenerateViewModel viewModel,
  required BeholdReadyActionInput actions,
}) {
  return Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildPrintOrientationBelowImage(viewModel: viewModel),
        const SizedBox(height: 10),
        _buildBeholdReadySecondaryLinks(
          context: context,
          viewModel: viewModel,
          actions: actions,
        ),
      ],
    ),
  );
}

Widget _buildBeholdReadySecondaryLinks({
  required BuildContext context,
  required PhotoGenerateViewModel viewModel,
  required BeholdReadyActionInput actions,
}) {
  final showTransformationDetails = viewModel.lastTransformationRunId != null;
  final showTotal = actions.paymentsEnabled && viewModel.selectedCount > 0;
  final canAddMoreStyle = viewModel.canShowAddAnotherStyleButton;

  return Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 8,
    runSpacing: 6,
    children: [
      if (showTransformationDetails)
        _buildTransformationDetailsStripLink(context, viewModel),
      if (showTotal) _buildSelectedTotalChip(viewModel),
      _buildDeletePhotosStripLink(
        context: context,
        viewModel: viewModel,
      ),
      _buildStartOverStripLink(context: context, viewModel: viewModel),
      if (canAddMoreStyle)
        _buildAddAnotherStyleStripLink(
          context: context,
          viewModel: viewModel,
          isMounted: actions.isMounted,
          onAddStyleSelected: actions.onAddStyleSelected,
        ),
    ],
  );
}

Widget _buildPrintOrientationBelowImage({
  required PhotoGenerateViewModel viewModel,
}) {
  final selectedOrientation = viewModel.printOrientation;
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'Print orientation',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      CupertinoSlidingSegmentedControl<PrintOrientation>(
        groupValue: selectedOrientation,
        backgroundColor: Colors.white.withValues(alpha: 0.12),
        thumbColor: const Color(0xFF22D3EE),
        children: {
          for (final orientation in PrintOrientation.values)
            orientation: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                orientation.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: orientation == selectedOrientation
                      ? const Color(0xFF0B1220)
                      : Colors.white.withValues(alpha: 0.85),
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

Widget _buildTransformationDetailsStripLink(
  BuildContext context,
  PhotoGenerateViewModel viewModel,
) {
  return TextButton.icon(
    onPressed: () {
      Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => TransformationDetailsScreen(
            runId: viewModel.lastTransformationRunId!,
            clientDisplayElapsedSeconds: viewModel.elapsedSeconds,
            fallbackSessionId: viewModel.sessionId,
          ),
        ),
      );
    },
    icon: Icon(
      Icons.photo_library_outlined,
      size: 15,
      color: kBeholdReadyAccent.withValues(alpha: 0.92),
    ),
    label: Text(
      AppStrings.beholdTransformationDetailsLink,
      style: TextStyle(
        color: kBeholdReadyAccent.withValues(alpha: 0.92),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );
}

Widget _buildDeletePhotosStripLink({
  required BuildContext context,
  required PhotoGenerateViewModel viewModel,
}) {
  return TextButton.icon(
    onPressed: () async {
      viewModel.cancelOperation();
      if (!context.mounted) return;
      await confirmAndDeleteMyPhotos(context);
    },
    icon: const Icon(
      CupertinoIcons.delete,
      size: 14,
      color: CupertinoColors.destructiveRed,
    ),
    label: const Text(
      AppStrings.deleteMyPhotosLabel,
      style: TextStyle(
        fontSize: 12,
        color: CupertinoColors.destructiveRed,
        decoration: TextDecoration.underline,
        fontWeight: FontWeight.w600,
      ),
    ),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );
}

Widget _buildStartOverStripLink({
  required BuildContext context,
  required PhotoGenerateViewModel viewModel,
}) {
  return TextButton.icon(
    onPressed: () async {
      viewModel.cancelOperation();
      await endPhotoboothCustomerSessionLogged('generate_start_over');
      if (!context.mounted) return;
      await Navigator.pushNamedAndRemoveUntil(
        context,
        AppConstants.kRouteTerms,
        (route) => false,
      );
    },
    icon: Icon(
      Icons.refresh_rounded,
      size: 15,
      color: Colors.white.withValues(alpha: 0.82),
    ),
    label: Text(
      'Start all over again',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.82),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
  );
}

Widget _buildAddAnotherStyleStripLink({
  required BuildContext context,
  required PhotoGenerateViewModel viewModel,
  required bool isMounted,
  required void Function(ThemeModel theme) onAddStyleSelected,
}) {
  return TextButton(
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
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: const Text(
      'Add another style',
      style: TextStyle(
        color: Colors.white70,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
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
  final label = viewModel.selectedCount < viewModel.generatedImages.length
      ? '${AppStrings.beholdContinueLabel} (${viewModel.selectedCount} of ${viewModel.generatedImages.length})'
      : AppStrings.beholdContinueLabel;

  return BeholdReadyContinueButton(
    label: label,
    enabled: canContinue,
    onPressed: canContinue
        ? () => _onPhotoGenerateContinuePressed(
              context: context,
              viewModel: viewModel,
              paymentsEnabled: paymentsEnabled,
            )
        : null,
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

  viewModel.trimMemoryWhenRouteInactive();

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

Widget _buildSelectedTotalChip(PhotoGenerateViewModel viewModel) {
  final extra = viewModel.selectedCount > 1
      ? '  (+₹${(viewModel.selectedCount - 1) * viewModel.additionalPrintPrice})'
      : '';
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    child: Text(
      'Total: ₹${viewModel.selectedTotalPrice}$extra',
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.78),
        fontSize: 12,
        fontWeight: FontWeight.w600,
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

  if (isGeneratingOrLoading) {
    final waitSize = computeBeholdHeroCardSize(
      context,
      maxWidth: screenWidth,
      maxHeight: math.min(
        maxRowHeight * 1.15,
        MediaQuery.sizeOf(context).height * 0.58,
      ),
      aspect: generationWaitHeroCellAspectRatio(viewModel.sessionPersonCount),
    );
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: GenerationWaitBody(
          viewModel: viewModel,
          cardWidth: waitSize.width,
          cardHeight: waitSize.height,
        ),
      ),
    );
  }

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
  if (hasImages) return AppStrings.beholdReadyTitle;
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
  bool headerInAppBar = false,
}) {
  if (hasImages && !isGeneratingOrLoading && headerInAppBar) {
    return const SizedBox.shrink();
  }
  if (hasImages && !isGeneratingOrLoading) {
    return const BeholdReadySuccessHeader();
  }
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
  final readyInAppBar =
      slot.hasImages && !slot.isGeneratingOrLoading && slot.fixedFooterOutside;
  final message = beholdHeroMessage(
    isGeneratingOrLoading: slot.isGeneratingOrLoading,
    isLoadingMore: slot.isLoadingMore,
    hasImages: slot.hasImages,
  );

  if (readyInAppBar) {
    final readySlots = builders.buildTransformedSlotWidgets(
      context,
      viewModel,
      appColors,
      slot.screenWidth,
      slot.maxRowHeight,
    );
    if (readySlots.isEmpty) {
      return _beholdReadyHeroMissingPlaceholder(
        width: slot.screenWidth,
        height: slot.maxRowHeight,
      );
    }
    return SizedBox(
      width: slot.screenWidth,
      height: slot.maxRowHeight,
      child: readySlots.first,
    );
  }

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
          headerInAppBar: readyInAppBar,
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
          headerInAppBar: slot.hasImages &&
              !slot.isGeneratingOrLoading &&
              slot.layout.fixedFooterOutside,
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
