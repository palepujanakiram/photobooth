import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/fotoflashback/fotoflashback_filter_viewmodel.dart';
import '../screens/fotoflashback/surprise_me_upsell_view.dart';
import '../screens/photo_generate/photo_generate_viewmodel.dart';
import '../services/app_settings_manager.dart';
import '../services/print_selection_coordinator.dart';
import 'app_strings.dart';
import 'constants.dart';
import 'payment_workflow_helpers.dart';
import 'route_args.dart';
import 'surprise_me_helpers.dart';

/// After the guest confirms a look: pre-pay (if configured) or compose → print selection.
Future<String?> continueAfterFlashbackLook({
  required BuildContext context,
  required FotoFlashbackFilterViewModel viewModel,
  required String? paymentCollectionTiming,
}) async {
  final paymentsEnabled = await resolvePaymentsEnabled();
  if (!context.mounted) return AppStrings.flashbackComposeFailed;

  final payBefore = paymentsEnabled &&
      collectPaymentBeforeGeneration(paymentCollectionTiming);
  if (payBefore) {
    await Navigator.of(context).pushNamed(
      AppConstants.kRoutePrePayment,
      arguments: FlashbackPrePayArgs(
        theme: viewModel.theme,
        imageDataUrls: viewModel.imageDataUrls,
        filterId: viewModel.selectedFilterId,
      ),
    );
    return null;
  }

  final image = await viewModel.compose();
  if (!context.mounted) return AppStrings.flashbackComposeFailed;
  if (image == null) {
    return viewModel.errorMessage ?? AppStrings.flashbackComposeFailed;
  }

  final stripImage = image.copyWith(
    printSize: viewModel.composeResult?.printSize ??
        AppConstants.kPrintSizeStripDual2x6,
  );
  final offer = await _offerSurpriseIfReady(context);
  if (!context.mounted) return AppStrings.flashbackComposeFailed;

  await navigateToFlashbackPrintSelection(
    context: context,
    image: stripImage,
    surpriseOffer: offer,
    printSize: viewModel.composeResult?.printSize,
    transformationRunId: viewModel.composeResult?.runId,
  );
  return null;
}

/// Compose after pre-payment approval, then open print selection.
Future<String?> composeFlashbackAfterPrePay({
  required BuildContext context,
  required FlashbackPrePayArgs args,
  FotoFlashbackFilterViewModel? viewModel,
}) async {
  final vm = viewModel ??
      FotoFlashbackFilterViewModel(
        theme: args.theme,
        imageDataUrls: args.imageDataUrls,
      );
  vm.selectFilter(args.filterId);
  final image = await vm.compose();
  if (!context.mounted) return AppStrings.flashbackComposeFailed;
  if (image == null) {
    return vm.errorMessage ?? AppStrings.flashbackComposeFailed;
  }

  final stripImage = image.copyWith(
    printSize: vm.composeResult?.printSize ??
        AppConstants.kPrintSizeStripDual2x6,
  );
  final offer = await _offerSurpriseIfReady(context);
  if (!context.mounted) return AppStrings.flashbackComposeFailed;

  await navigateToFlashbackPrintSelection(
    context: context,
    image: stripImage,
    surpriseOffer: offer,
    printSize: vm.composeResult?.printSize,
    transformationRunId: vm.composeResult?.runId,
  );
  return null;
}

Future<SurpriseMeOfferResult?> _offerSurpriseIfReady(
  BuildContext context,
) async {
  if (!context.mounted) return null;
  final settings = context.read<AppSettingsManager>().settings;
  return maybeOfferSurpriseMeCopy(
    context: context,
    enableSurpriseMeAi: settings?.enableSurpriseMeAi == true,
    additionalPrintPrice: settings?.additionalPrintPrice ??
        AppConstants.kDefaultAdditionalPrintPrice,
  );
}

/// Opens the print-selection hub with strip (+ optional Surprise Me AI).
Future<void> navigateToFlashbackPrintSelection({
  required BuildContext context,
  required GeneratedImage image,
  SurpriseMeOfferResult? surpriseOffer,
  String? printSize,
  String? transformationRunId,
}) async {
  if (!context.mounted) return;
  final size = printSize?.trim();
  final runId = transformationRunId?.trim();
  final strip = image.copyWith(
    isSelected: true,
    printSize: image.printSize ??
        ((size != null && size.isNotEmpty)
            ? size
            : AppConstants.kPrintSizeStripDual2x6),
  );
  final offer = surpriseOffer;
  final surpriseImage = offer?.image;
  final includeSurprise = offer != null &&
      surpriseImage != null &&
      (offer.choice == SurpriseMeUpsellChoice.accept ||
          offer.choice == SurpriseMeUpsellChoice.exploreMore);
  final images = <GeneratedImage>[
    strip,
    if (includeSurprise) surpriseImage.copyWith(isSelected: true),
  ];
  final resolvedSize = (size != null && size.isNotEmpty)
      ? size
      : AppConstants.kPrintSizeStripDual2x6;
  final resolvedRunId =
      (runId != null && runId.isNotEmpty) ? runId : null;

  final coordinator = PrintSelectionCoordinator.instance;
  coordinator.seed(
    seedImages: images,
    stripPrintSize: resolvedSize,
    transformationRunId: resolvedRunId,
    fromClassicStrip: true,
  );
  if (surpriseOffer?.choice == SurpriseMeUpsellChoice.exploreMore) {
    coordinator.markExploreMore();
  }

  await Navigator.of(context).pushNamedAndRemoveUntil(
    AppConstants.kRoutePrintSelection,
    (route) =>
        route.settings.name == AppConstants.kRouteExperienceChoice ||
        route.settings.name == AppConstants.kRouteTerms ||
        route.settings.name == AppConstants.kRouteHome ||
        route.isFirst,
    arguments: PrintSelectionArgs(
      generatedImages: images,
      stripPrintSize: resolvedSize,
      transformationRunId: resolvedRunId,
    ),
  );
}

/// Legacy alias used by older tests / call sites.
Future<void> navigateToFlashbackResult({
  required BuildContext context,
  required GeneratedImage image,
  GeneratedImage? surpriseImage,
  String? printSize,
  String? transformationRunId,
}) {
  return navigateToFlashbackPrintSelection(
    context: context,
    image: image,
    surpriseOffer: surpriseImage == null
        ? null
        : SurpriseMeOfferResult(
            choice: SurpriseMeUpsellChoice.accept,
            image: surpriseImage,
          ),
    printSize: printSize,
    transformationRunId: transformationRunId,
  );
}

/// CTA label that mirrors AI: pay now vs continue to result checkout.
String flashbackContinueCta({
  required bool paymentsEnabled,
  required String? paymentCollectionTiming,
}) {
  if (paymentsEnabled &&
      collectPaymentBeforeGeneration(paymentCollectionTiming)) {
    return AppStrings.flashbackComposePayCta;
  }
  return AppStrings.flashbackComposeCta;
}
