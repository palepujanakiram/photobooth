import 'package:flutter/material.dart';

import '../../models/app_settings_model.dart';
import '../../utils/constants.dart';

/// UI helpers for [StaffPaymentsScreen] (Sonar S3776 / S3358 extractions).
Color staffPaymentStatusBadgeColor(String status) {
  if (status == 'APPROVED') {
    return Colors.green.withValues(alpha: 0.12);
  }
  if (status == 'FAILED' || status == 'REJECTED') {
    return Colors.red.withValues(alpha: 0.12);
  }
  return Colors.orange.withValues(alpha: 0.12);
}

({String host, int port}) staffPaymentsPrinterEndpoint(AppSettingsModel? settings) {
  final host = (settings?.printerHost?.trim().isNotEmpty ?? false)
      ? settings!.printerHost!.trim()
      : AppConstants.kDefaultPrinterHost;
  final port = (settings?.printerPort != null &&
          settings!.printerPort! > 0 &&
          settings.printerPort! <= 65535)
      ? settings.printerPort!
      : 80;
  return (host: host, port: port);
}
