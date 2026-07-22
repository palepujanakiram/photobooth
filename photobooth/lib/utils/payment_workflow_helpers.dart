import 'package:flutter/material.dart';

import '../screens/photo_capture/photo_model.dart';
import '../screens/theme_selection/theme_model.dart';
import '../services/kiosk_manager.dart';
import 'constants.dart';
import 'route_args.dart';

/// True when account settings request UPI collection before AI generation.
bool collectPaymentBeforeGeneration(String? timing) =>
    timing == AppConstants.kPaymentCollectionBeforeGeneration;

/// Physical sheets = selected images × copies per image (min 1 copy).
int resolvePrintSheetCount({
  required int imageCount,
  int copiesPerImage = AppConstants.kDefaultPrintCopies,
}) {
  if (imageCount <= 0) return 0;
  final copies = copiesPerImage.clamp(
    AppConstants.kDefaultPrintCopies,
    AppConstants.kMaxPrintCopies,
  );
  return imageCount * copies;
}

/// Amount due at the post-generation Pay screen.
///
/// When payment was collected before generation, the initial print price is
/// already covered; only additional sheets are charged at checkout.
///
/// [sheetCount] is total physical prints (images × copies). Defaults to one
/// sheet per image when [copiesPerImage] is omitted and [imageCount] is used.
int resolveCheckoutAmount({
  required bool collectPaymentBeforeGeneration,
  required int imageCount,
  required int initialPrintPrice,
  required int additionalPrintPrice,
  int copiesPerImage = AppConstants.kDefaultPrintCopies,
}) {
  final sheetCount = resolvePrintSheetCount(
    imageCount: imageCount,
    copiesPerImage: copiesPerImage,
  );
  if (sheetCount <= 0) return 0;
  final fullTotal = initialPrintPrice +
      (sheetCount > 1 ? (sheetCount - 1) * additionalPrintPrice : 0);
  if (!collectPaymentBeforeGeneration) return fullTotal;
  return sheetCount > 1 ? (sheetCount - 1) * additionalPrintPrice : 0;
}

/// Route after frame/theme selection when generation is next.
String resolvePostFrameRoute({
  required bool paymentsEnabled,
  required String? paymentCollectionTiming,
}) {
  if (paymentsEnabled &&
      collectPaymentBeforeGeneration(paymentCollectionTiming)) {
    return AppConstants.kRoutePrePayment;
  }
  return AppConstants.kRouteGenerateProgress;
}

/// Kiosk payment enablement: false override skips all payment screens.
Future<bool> resolvePaymentsEnabled() async {
  final override = await KioskManager().getPaymentEnabledOverride();
  return override ?? true;
}

/// Navigates to pre-payment or generation based on account payment timing.
Future<void> navigateToGenerationOrPrePayment({
  required BuildContext context,
  required PhotoModel photo,
  required ThemeModel theme,
  required bool replace,
  String? paymentCollectionTiming,
}) async {
  final paymentsEnabled = await resolvePaymentsEnabled();
  if (!context.mounted) return;
  final route = resolvePostFrameRoute(
    paymentsEnabled: paymentsEnabled,
    paymentCollectionTiming: paymentCollectionTiming,
  );
  final args = GenerateArgs(photo: photo, theme: theme);
  if (replace) {
    await Navigator.pushReplacementNamed(context, route, arguments: args);
  } else {
    await Navigator.pushNamed(context, route, arguments: args);
  }
}
