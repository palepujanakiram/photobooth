import 'dart:async';

import '../models/payment_mode.dart';
import '../models/strip_models.dart';
import '../services/local_kiosk_models.dart';
import '../services/local_session_skeleton.dart';
import 'constants.dart';
import 'exceptions.dart';

/// Guest and staff UX when the kiosk cannot reach Fly (P6).
abstract final class KioskOfflineUx {
  static bool sessionPayloadIsOffline(Map<String, dynamic>? json) =>
      json != null && json[kKioskSessionOfflineKey] == true;

  /// Skip Gemini / Fly generate. Do not queue AI on the line.
  static bool shouldSkipAiGeneration({
    required bool sessionOffline,
    Object? error,
  }) {
    if (sessionOffline) return true;
    if (error == null) return false;
    return isWanDownSessionError(error);
  }

  /// Hide UPI QR; cash / pay at counter only.
  static bool shouldUseCashOnlyPayments({
    required bool sessionOffline,
    Object? error,
  }) =>
      shouldSkipAiGeneration(sessionOffline: sessionOffline, error: error);

  /// Coupons / gift cards are cloud-only.
  static bool shouldHideCloudDiscounts({required bool sessionOffline}) =>
      sessionOffline;

  /// Skip the UPI pre-pay screen; cash is collected after print-ready photos.
  static bool shouldSkipUpiPrePayment({required bool sessionOffline}) =>
      sessionOffline;

  /// Skip Fly `/api/preprocess-image` (Gemini). Use on-device face count.
  static bool shouldSkipGeminiPreprocess({
    required bool sessionOffline,
    Object? error,
  }) =>
      shouldSkipAiGeneration(sessionOffline: sessionOffline, error: error);

  /// 4-shot local look instead of Fly `composeStrip`.
  ///
  /// Online compose timeouts stay failures (existing UX). Network / 5xx
  /// ApiExceptions fall back to a baked look.
  static bool shouldUseLocalStripLook({
    required bool sessionOffline,
    Object? error,
  }) {
    if (sessionOffline) return true;
    if (error == null) return false;
    if (error is TimeoutException) return false;
    if (error is ApiException) {
      final code = error.statusCode;
      if (code != null && code >= 500) return true;
      return error.message == AppConstants.kErrorNetwork;
    }
    return false;
  }

  /// Pick-a-look already has a built-in catalog — do not show raw Fly DNS /
  /// connection errors when the session is offline or the host is unreachable.
  static bool shouldSilenceStripCatalogLoadError({
    required bool sessionOffline,
    Object? error,
  }) {
    if (sessionOffline) return true;
    if (error == null) return false;
    if (error is TimeoutException) return false;
    final msg = error is ApiException ? error.message : error.toString();
    if (msg == AppConstants.kErrorNetwork) return true;
    final lower = msg.toLowerCase();
    if (lower.contains('failed host lookup') ||
        lower.contains('connection errored') ||
        lower.contains('socketexception') ||
        lower.contains('network is unreachable') ||
        lower.contains('connection refused')) {
      return true;
    }
    if (error is ApiException) {
      final code = error.statusCode;
      if (code != null && code >= 500) return true;
    }
    return false;
  }
}

String firstNonEmptyDataUrl(Iterable<String> urls) {
  for (final url in urls) {
    final trimmed = url.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

StripComposeResult localLookComposeResult({
  required String imageUrl,
  required String filterId,
  required String printSize,
}) {
  return StripComposeResult(
    imageUrl: imageUrl,
    filter: filterId,
    copiesOnSheet: 1,
    printSize: printSize,
  );
}

class LocalBoothCloseTotals {
  const LocalBoothCloseTotals({
    required this.sessions,
    required this.printJobs,
    required this.receipts,
    required this.paymentCount,
    required this.cashCount,
    required this.cashAmount,
  });

  final int sessions;
  final int printJobs;
  final int receipts;
  final int paymentCount;
  final int cashCount;
  final int cashAmount;
}

LocalBoothCloseTotals localBoothCloseTotals({
  required LocalDayCounts counts,
  required Iterable<Map<String, dynamic>> paymentPayloads,
}) {
  var cashCount = 0;
  var cashAmount = 0;
  for (final payload in paymentPayloads) {
    final mode = payload['paymentMode']?.toString().trim().toUpperCase();
    if (mode != PaymentMode.cash.apiValue) continue;
    cashCount++;
    final amount = jsonInt(payload['amount']);
    cashAmount += amount < 0 ? 0 : amount;
  }
  return LocalBoothCloseTotals(
    sessions: counts.sessions,
    printJobs: counts.printJobs,
    receipts: counts.receipts,
    paymentCount: counts.payments,
    cashCount: cashCount,
    cashAmount: cashAmount,
  );
}
