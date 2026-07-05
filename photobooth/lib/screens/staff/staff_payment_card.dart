import 'package:flutter/material.dart';

import '../../views/widgets/app_colors.dart';
import 'staff_payments_payload_utils.dart';
import 'staff_payments_view_helpers.dart';

/// Single payment row card (Sonar S3776 extraction from staff payments list).
class StaffPaymentCard extends StatelessWidget {
  const StaffPaymentCard({
    super.key,
    required this.appColors,
    required this.paymentId,
    required this.status,
    required this.sessionId,
    required this.amount,
    required this.thumb,
    this.onThumbTap,
    required this.loading,
    required this.showDecisionButtons,
    required this.onApprove,
    required this.onReject,
    required this.onPrint,
  });

  final AppColors appColors;
  final String paymentId;
  final String status;
  final String sessionId;
  final String amount;
  final Widget thumb;
  final VoidCallback? onThumbTap;
  final bool loading;
  final bool showDecisionButtons;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: onThumbTap,
                  child: thumb,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              paymentId.isEmpty ? '(no id)' : paymentId,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: staffPaymentStatusBadgeColor(status),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              status.isEmpty ? 'UNKNOWN' : status,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (amount.isNotEmpty)
                        Text(
                          'Amount: $amount',
                          style: TextStyle(color: appColors.textColor),
                        ),
                      if (sessionId.isNotEmpty)
                        Text(
                          'Session: $sessionId',
                          style: TextStyle(color: appColors.textColor),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (showDecisionButtons)
                  ElevatedButton(
                    onPressed: loading ? null : onApprove,
                    child: const Text('Approve'),
                  ),
                if (showDecisionButtons)
                  OutlinedButton(
                    onPressed: loading ? null : onReject,
                    child: const Text('Reject'),
                  ),
                OutlinedButton.icon(
                  onPressed: (loading || sessionId.isEmpty) ? null : onPrint,
                  icon: const Icon(Icons.print),
                  label: const Text('Print'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String amountFromPayload(Map<String, dynamic> p) {
    return StaffPaymentsPayloadUtils.pickString(
      p,
      const ['amount', 'total', 'price'],
    );
  }
}
