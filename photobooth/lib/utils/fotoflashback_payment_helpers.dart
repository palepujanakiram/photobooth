import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/fotoflashback/fotoflashback_filter_viewmodel.dart';
import '../screens/photo_generate/photo_generate_viewmodel.dart';
import '../services/app_settings_manager.dart';
import 'app_strings.dart';
import 'constants.dart';
import 'payment_workflow_helpers.dart';
import 'print_orientation.dart';
import 'route_args.dart';
import 'surprise_me_helpers.dart';

/// After the guest confirms a look: pre-pay (if configured) or compose → Result.
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
  final surprise = await _offerSurpriseIfReady(context);
  if (!context.mounted) return AppStrings.flashbackComposeFailed;

  await navigateToFlashbackResult(
    context: context,
    image: stripImage,
    surpriseImage: surprise,
    printSize: viewModel.composeResult?.printSize,
    transformationRunId: viewModel.composeResult?.runId,
  );
  return null;
}

/// Compose after pre-payment approval, then open Result.
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
  final surprise = await _offerSurpriseIfReady(context);
  if (!context.mounted) return AppStrings.flashbackComposeFailed;

  await navigateToFlashbackResult(
    context: context,
    image: stripImage,
    surpriseImage: surprise,
    printSize: vm.composeResult?.printSize,
    transformationRunId: vm.composeResult?.runId,
  );
  return null;
}

Future<GeneratedImage?> _offerSurpriseIfReady(BuildContext context) async {
  if (!context.mounted) return null;
  final settings = context.read<AppSettingsManager>().settings;
  return maybeOfferSurpriseMeCopy(
    context: context,
    enableSurpriseMeAi: settings?.enableSurpriseMeAi == true,
    additionalPrintPrice: settings?.additionalPrintPrice ??
        AppConstants.kDefaultAdditionalPrintPrice,
  );
}

Future<void> navigateToFlashbackResult({
  required BuildContext context,
  required GeneratedImage image,
  GeneratedImage? surpriseImage,
  String? printSize,
  String? transformationRunId,
}) async {
  if (!context.mounted) return;
  final size = printSize?.trim();
  final runId = transformationRunId?.trim();
  final images = <GeneratedImage>[
    image.copyWith(
      printSize: image.printSize ??
          ((size != null && size.isNotEmpty)
              ? size
              : AppConstants.kPrintSizeStripDual2x6),
    ),
    if (surpriseImage != null) surpriseImage,
  ];
  await Navigator.of(context).pushNamedAndRemoveUntil(
    AppConstants.kRouteResult,
    (route) =>
        route.settings.name == AppConstants.kRouteExperienceChoice ||
        route.settings.name == AppConstants.kRouteTerms ||
        route.settings.name == AppConstants.kRouteHome ||
        route.isFirst,
    arguments: ResultArgs(
      generatedImages: images,
      printOrientation: PrintOrientation.portrait,
      // WCM "6x2*2" cut (`s6x2_2`) — not s4x6 (uncut) or s2x6 (single strip).
      // Per-image [GeneratedImage.printSize] overrides this for the AI add-on.
      printSize: (size != null && size.isNotEmpty)
          ? size
          : AppConstants.kPrintSizeStripDual2x6,
      transformationRunId:
          (runId != null && runId.isNotEmpty) ? runId : null,
    ),
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
