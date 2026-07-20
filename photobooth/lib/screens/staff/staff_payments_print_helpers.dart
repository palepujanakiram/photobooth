import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../models/app_settings_model.dart';
import '../../models/session_print_receipt_result.dart';
import '../../services/staff_api_service.dart';
import '../../services/print_service.dart';
import '../../services/receipt_printer_service.dart';
import '../../utils/app_strings.dart';
import '../../utils/exceptions.dart';
import '../../utils/printer_endpoint.dart';

/// Staff payment print flow state updates (Sonar S3776 extraction).
typedef StaffPaymentsPrintStateSink = void Function({
  bool? loading,
  String? error,
  String? progressMessage,
});

/// True when admin enabled a LAN thermal receipt printer with a host.
bool staffPaymentsIsReceiptPrinterConfigured(AppSettingsModel? settings) {
  if (settings?.receiptPrinterEnabled != true) return false;
  final host = settings?.receiptPrinterHost?.trim() ?? '';
  return host.isNotEmpty;
}

/// Validates session, confirms print, and resolves image URL (Sonar S3776).
Future<String?> staffPaymentsPreparePrintSession({
  required BuildContext context,
  required bool Function() isMounted,
  required String sessionId,
  required Future<String?> Function() resolveImageUrl,
  required void Function(String message) onError,
}) async {
  if (sessionId.isEmpty) {
    onError('Missing sessionId in payment payload');
    return null;
  }

  final ok = await staffPaymentsConfirmPrintDialog(context, sessionId);
  if (!isMounted() || !ok) return null;

  final imageUrl = await resolveImageUrl();
  if (!isMounted()) return null;
  if (imageUrl == null || imageUrl.isEmpty) {
    onError('Cannot print: image URL not found for this session.');
    return null;
  }
  return imageUrl;
}

/// Confirms print for a session; returns false if cancelled or unmounted.
Future<bool> staffPaymentsConfirmPrintDialog(
  BuildContext context,
  String sessionId,
) async {
  final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Create print job?'),
          content: Text('Session: $sessionId'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Print'),
            ),
          ],
        ),
      ) ??
      false;
  return ok;
}

/// Confirms thermal receipt print; returns false if cancelled or unmounted.
Future<bool> staffPaymentsConfirmReceiptPrintDialog(
  BuildContext context,
  String sessionId,
) async {
  final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(AppStrings.printReceiptButton),
          content: Text('Print receipt for session:\n$sessionId'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text(AppStrings.printReceiptButton),
            ),
          ],
        ),
      ) ??
      false;
  return ok;
}

/// Download image and send to network printer (Sonar S3776 extraction).
Future<void> staffPaymentsRunPrintJob({
  required StaffApiService staffApi,
  required PrintService printService,
  required AppSettingsModel? settings,
  required String imageUrl,
  required bool Function() isMounted,
  required StaffPaymentsPrintStateSink onState,
  required VoidCallback? onSuccess,
}) async {
  onState(loading: true, error: null, progressMessage: 'Preparing image...');
  try {
    final endpoint = resolvePrinterEndpoint(settings);
    final file = await staffApi.downloadImageToTemp(
      imageUrl,
      onProgress: (m) {
        if (!isMounted()) return;
        onState(progressMessage: m);
      },
    );

    onState(progressMessage: 'Sending print job...');
    await printService.printImageToNetworkPrinter(
      file,
      printerHost: endpoint.host,
      printerPort: endpoint.port,
      printerPath: endpoint.path,
    );
    if (!isMounted()) return;
    onSuccess?.call();
  } on ApiException catch (e) {
    if (!isMounted()) return;
    onState(error: e.message);
  } on PrintException catch (e) {
    if (!isMounted()) return;
    onState(error: e.message);
  } catch (e) {
    if (!isMounted()) return;
    onState(error: 'Print failed: $e');
  } finally {
    if (isMounted()) onState(loading: false);
  }
}

/// Fetch ESC/POS from API and deliver to the LAN thermal receipt printer.
Future<void> staffPaymentsRunReceiptPrintJob({
  required StaffApiService staffApi,
  required ReceiptPrinterService receiptPrinter,
  required AppSettingsModel? settings,
  required String sessionId,
  required bool Function() isMounted,
  required StaffPaymentsPrintStateSink onState,
  required VoidCallback? onSuccess,
}) async {
  if (sessionId.trim().isEmpty) {
    onState(error: 'Missing sessionId in payment payload');
    return;
  }
  if (kIsWeb) {
    onState(error: AppStrings.receiptPrintUnsupportedOnWeb);
    return;
  }
  if (!staffPaymentsIsReceiptPrinterConfigured(settings)) {
    onState(error: AppStrings.receiptPrintNotConfigured);
    return;
  }

  onState(
    loading: true,
    error: null,
    progressMessage: AppStrings.printingReceiptButton,
  );
  try {
    final raw = await staffApi.postSessionPrintReceipt(sessionId: sessionId);
    if (!isMounted()) return;

    final result = SessionPrintReceiptResult.fromJson(raw);
    final deliverError = staffPaymentsReceiptDeliverError(result);
    if (deliverError != null) {
      onState(error: deliverError);
      return;
    }

    if (result.deliveredByServer) {
      onSuccess?.call();
      return;
    }

    onState(progressMessage: 'Sending to receipt printer...');
    await receiptPrinter.sendEscPosBase64(
      host: result.host!.trim(),
      port: result.port,
      payloadBase64: result.payloadBase64!,
    );
    if (!isMounted()) return;
    onSuccess?.call();
  } on ApiException catch (e) {
    if (!isMounted()) return;
    onState(error: e.message);
  } catch (e) {
    if (!isMounted()) return;
    onState(error: '${AppStrings.receiptPrintFailedGeneric} ($e)');
  } finally {
    if (isMounted()) onState(loading: false);
  }
}

/// Maps a print-receipt API result to a staff-facing error, or null if OK to send.
String? staffPaymentsReceiptDeliverError(SessionPrintReceiptResult result) {
  if (!result.success || !result.printerConfigured) {
    return result.error ??
        result.message ??
        AppStrings.receiptPrintNotConfigured;
  }
  if (result.deliveredByServer) return null;
  if (!result.needsLanDelivery) {
    return AppStrings.receiptPrintEmptyPayload;
  }
  return null;
}
