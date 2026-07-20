import 'package:flutter/material.dart';

import '../../models/payment_mode.dart';
import '../../utils/app_strings.dart';
import '../../views/widgets/app_colors.dart';
import 'staff_payments_payload_utils.dart';
import 'staff_payments_view_helpers.dart';

/// Identity + amount fields for [StaffPaymentCard] (keeps ctor under S107).
class StaffPaymentCardData {
  const StaffPaymentCardData({
    required this.paymentId,
    required this.status,
    required this.sessionId,
    required this.amount,
    this.recordedPaymentMode,
  });

  final String paymentId;
  final String status;
  final String sessionId;
  final String amount;
  final PaymentMode? recordedPaymentMode;
}

/// Actions + decision controls for [StaffPaymentCard].
class StaffPaymentCardActions {
  const StaffPaymentCardActions({
    required this.thumb,
    this.onThumbTap,
    required this.loading,
    required this.showDecisionButtons,
    required this.selectedMode,
    required this.onModeChanged,
    required this.onApprove,
    required this.onReject,
    required this.onPrint,
    this.onPrintReceipt,
  });

  final Widget thumb;
  final VoidCallback? onThumbTap;
  final bool loading;
  final bool showDecisionButtons;
  final PaymentMode selectedMode;
  final ValueChanged<PaymentMode> onModeChanged;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onPrint;

  /// When non-null, shows a "Print receipt" button (receipt printer configured).
  final VoidCallback? onPrintReceipt;
}

/// Single payment row card (Sonar S3776 extraction from staff payments list).
class StaffPaymentCard extends StatelessWidget {
  const StaffPaymentCard({
    super.key,
    required this.appColors,
    required this.data,
    required this.actions,
  });

  final AppColors appColors;
  final StaffPaymentCardData data;
  final StaffPaymentCardActions actions;

  @override
  Widget build(BuildContext context) {
    final paymentId = data.paymentId;
    final status = data.status;
    final amount = data.amount;
    final sessionId = data.sessionId;
    final loading = actions.loading;
    final showDecisionButtons = actions.showDecisionButtons;

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
                  onTap: actions.onThumbTap,
                  child: actions.thumb,
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
                          'Amount: ${AppStrings.currencyRupee}$amount',
                          style: TextStyle(color: appColors.textColor),
                        ),
                      if (sessionId.isNotEmpty)
                        Text(
                          'Session: $sessionId',
                          style: TextStyle(color: appColors.textColor),
                        ),
                      if (!showDecisionButtons &&
                          data.recordedPaymentMode != null)
                        Text(
                          'Mode: ${data.recordedPaymentMode!.label}',
                          style: TextStyle(color: appColors.textColor),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (showDecisionButtons) ...[
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: AppStrings.paymentModeLabel,
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<PaymentMode>(
                    value: actions.selectedMode,
                    isExpanded: true,
                    isDense: true,
                    items: [
                      for (final m in PaymentMode.apiOrder)
                        DropdownMenuItem(value: m, child: Text(m.label)),
                    ],
                    onChanged: loading
                        ? null
                        : (v) {
                            if (v != null) actions.onModeChanged(v);
                          },
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (showDecisionButtons)
                  ElevatedButton(
                    onPressed: loading ? null : actions.onApprove,
                    child: const Text('Approve'),
                  ),
                if (showDecisionButtons)
                  OutlinedButton(
                    onPressed: loading ? null : actions.onReject,
                    child: const Text('Reject'),
                  ),
                OutlinedButton.icon(
                  onPressed: (loading || sessionId.isEmpty)
                      ? null
                      : actions.onPrint,
                  icon: const Icon(Icons.print),
                  label: const Text('Print'),
                ),
                if (actions.onPrintReceipt != null)
                  OutlinedButton.icon(
                    onPressed: (loading || sessionId.isEmpty)
                        ? null
                        : actions.onPrintReceipt,
                    icon: const Icon(Icons.receipt_long),
                    label: const Text(AppStrings.printReceiptButton),
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
