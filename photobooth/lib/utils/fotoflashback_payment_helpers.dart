import 'package:flutter/material.dart';

import '../screens/fotoflashback/fotoflashback_filter_viewmodel.dart';
import '../screens/photo_generate/photo_generate_viewmodel.dart';
import 'app_strings.dart';
import 'constants.dart';
import 'payment_workflow_helpers.dart';
import 'print_orientation.dart';
import 'route_args.dart';

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
        surpriseMeAi: viewModel.surpriseMeAi,
      ),
    );
    return null;
  }

  final image = await viewModel.compose();
  if (!context.mounted) return AppStrings.flashbackComposeFailed;
  if (image == null) {
    return viewModel.errorMessage ?? AppStrings.flashbackComposeFailed;
  }
  await navigateToFlashbackResult(
    context: context,
    image: image,
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
        surpriseMeAi: args.surpriseMeAi,
      );
  if (!args.surpriseMeAi) {
    vm.selectFilter(args.filterId);
  }
  final image = await vm.compose();
  if (!context.mounted) return AppStrings.flashbackComposeFailed;
  if (image == null) {
    return vm.errorMessage ?? AppStrings.flashbackComposeFailed;
  }
  await navigateToFlashbackResult(
    context: context,
    image: image,
    printSize: vm.composeResult?.printSize,
    transformationRunId: vm.composeResult?.runId,
  );
  return null;
}

Future<void> navigateToFlashbackResult({
  required BuildContext context,
  required GeneratedImage image,
  String? printSize,
  String? transformationRunId,
}) async {
  if (!context.mounted) return;
  final size = printSize?.trim();
  final runId = transformationRunId?.trim();
  await Navigator.of(context).pushNamedAndRemoveUntil(
    AppConstants.kRouteResult,
    (route) =>
        route.settings.name == AppConstants.kRouteExperienceChoice ||
        route.settings.name == AppConstants.kRouteTerms ||
        route.settings.name == AppConstants.kRouteHome ||
        route.isFirst,
    arguments: ResultArgs(
      generatedImages: [image],
      printOrientation: PrintOrientation.portrait,
      // WCM "6x2*2" cut (`s6x2_2`) — not s4x6 (uncut) or s2x6 (single strip).
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
