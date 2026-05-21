import 'package:flutter/material.dart';

import '../../models/app_settings_model.dart';
import '../../services/api_service.dart';
import '../../services/print_service.dart';
import '../../utils/exceptions.dart';
import 'staff_payments_view_helpers.dart';

/// Staff payment print flow state updates (Sonar S3776 extraction).
typedef StaffPaymentsPrintStateSink = void Function({
  bool? loading,
  String? error,
  String? progressMessage,
});

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
  required BuildContext context,
  required ApiService publicApi,
  required PrintService printService,
  required AppSettingsModel? settings,
  required String imageUrl,
  required bool Function() isMounted,
  required StaffPaymentsPrintStateSink onState,
}) async {
  onState(loading: true, error: null, progressMessage: 'Preparing image...');
  try {
    final endpoint = staffPaymentsPrinterEndpoint(settings);
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
    );
    if (!isMounted()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Print job sent')),
    );
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
