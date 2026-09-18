import 'package:flutter/material.dart';

import '../screens/photo_capture/photo_model.dart';
import '../screens/theme_selection/theme_model.dart';
import '../services/event_manager.dart';
import '../services/kiosk_manager.dart';
import 'app_strings.dart';
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
  bool wanDown = false,
}) {
  if (wanDown) return AppConstants.kRouteGenerateProgress;
  if (paymentsEnabled &&
      collectPaymentBeforeGeneration(paymentCollectionTiming)) {
    return AppConstants.kRoutePrePayment;
  }
  return AppConstants.kRouteGenerateProgress;
}

/// Kiosk payment enablement: false override skips UPI.
/// Event-bound booths collect cash at the counter instead of UPI.
Future<bool> resolvePaymentsEnabled() async {
  if (await EventManager().isEventBound()) return false;
  final override = await KioskManager().getPaymentEnabledOverride();
  return override ?? true;
}

/// True when UPI is off — Pay screen collects cash (copies + staff approve).
bool shouldCollectCounterCash({required bool paymentsEnabled}) =>
    !paymentsEnabled;

/// Always false: Pay collect stays on so staff can record cash.
bool shouldSkipOfflinePayCollect({
  required bool paymentsEnabled,
  required bool sessionOffline,
}) =>
    false;

/// App-bar line on PAY — one short cue, not repeated in the card.
String payScreenAppBarSubtitle({
  required bool collectsCounterCash,
  required bool sessionOffline,
}) {
  if (!collectsCounterCash) return AppStrings.payScanToComplete;
  if (sessionOffline) return AppStrings.wanDownCashAppBarSubtitle;
  return AppStrings.counterCashAppBarSubtitle;
}

/// Intro under PAY title. Null for cash so the card is not duplicated.
String? payScreenIntroMessage({required bool collectsCounterCash}) {
  if (collectsCounterCash) return null;
  return AppStrings.payUpiIntro;
}

/// Status under the cash/QR slot.
String payScreenCashStatus({required bool sessionOffline}) {
  if (sessionOffline) return AppStrings.offlineCashOnlyWaiting;
  return AppStrings.counterCashOnlyWaiting;
}

/// PIN "cash received" is only for native WAN-down; web staff use Payments.
bool payScreenShowsStaffPinConfirm({
  required bool sessionOffline,
  required bool isWeb,
  bool skipOfflineCashPin = false,
  bool autoApproveCashPrint = false,
}) =>
    sessionOffline &&
    !isWeb &&
    !skipCashStaffApproval(
      skipOfflineCashPin: skipOfflineCashPin,
      autoApproveCashPrint: autoApproveCashPrint,
    );

/// Skip booth PIN and/or Payments wait — cash is recorded and print starts.
bool skipCashStaffApproval({
  bool skipOfflineCashPin = false,
  bool autoApproveCashPrint = false,
}) =>
    skipOfflineCashPin || autoApproveCashPrint;

/// Navigates to pre-payment or generation based on account payment timing.
Future<void> navigateToGenerationOrPrePayment({
  required BuildContext context,
  required PhotoModel photo,
  required ThemeModel theme,
  required bool replace,
  String? paymentCollectionTiming,
  bool wanDown = false,
}) async {
  final paymentsEnabled = await resolvePaymentsEnabled();
  if (!context.mounted) return;
  final route = resolvePostFrameRoute(
    paymentsEnabled: paymentsEnabled,
    paymentCollectionTiming: paymentCollectionTiming,
    wanDown: wanDown,
  );
  final args = GenerateArgs(photo: photo, theme: theme);
  if (replace) {
    await Navigator.pushReplacementNamed(context, route, arguments: args);
  } else {
    await Navigator.pushNamed(context, route, arguments: args);
  }
}
