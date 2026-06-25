import 'package:flutter/material.dart';

import '../../models/app_settings_model.dart';
import '../../utils/printer_endpoint.dart';

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
  final endpoint = resolvePrinterEndpoint(settings);
  return (host: endpoint.host, port: endpoint.port);
}
