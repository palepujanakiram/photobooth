import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/staff/staff_payments_view_helpers.dart';

void main() {
  test('staffPaymentStatusBadgeColor distinguishes cancelled from rejected', () {
    expect(
      staffPaymentStatusBadgeColor('APPROVED'),
      Colors.green.withValues(alpha: 0.12),
    );
    expect(
      staffPaymentStatusBadgeColor('REJECTED'),
      Colors.red.withValues(alpha: 0.12),
    );
    expect(
      staffPaymentStatusBadgeColor('CANCELLED'),
      Colors.blueGrey.withValues(alpha: 0.12),
    );
    expect(
      staffPaymentStatusBadgeColor('PENDING'),
      Colors.orange.withValues(alpha: 0.12),
    );
  });
}
