import 'package:flutter/material.dart';

import '../../models/app_settings_model.dart';
import '../../services/api_service.dart';
import '../../services/print_service.dart';
import '../../utils/exceptions.dart';
import '../../utils/printer_endpoint.dart';
import 'staff_payments_view_helpers.dart';

/// Staff payment print flow state updates (Sonar S3776 extraction).
typedef StaffPaymentsPrintStateSink = void Function({
  bool? loading,
  String? error,
  String? progressMessage,
});

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

/// Download image and send to network printer (Sonar S3776 extraction).
Future<void> staffPaymentsRunPrintJob({
  required ApiService publicApi,
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
    final file = await publicApi.downloadImageToTemp(
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
