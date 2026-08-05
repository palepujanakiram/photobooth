import 'package:flutter/material.dart';

/// UI helpers for [StaffPaymentsScreen] (Sonar S3776 / S3358 extractions).
Color staffPaymentStatusBadgeColor(String status) {
  if (status == 'APPROVED') {
    return Colors.green.withValues(alpha: 0.12);
  }
  if (status == 'FAILED' || status == 'REJECTED') {
    return Colors.red.withValues(alpha: 0.12);
  }
  // Superseded unpaid QR / voided pending — not a staff reject.
  if (status == 'CANCELLED' || status == 'CANCELED') {
    return Colors.blueGrey.withValues(alpha: 0.12);
  }
  return Colors.orange.withValues(alpha: 0.12);
}
