import 'package:flutter/material.dart';

import '../../models/session_discount.dart';
import '../../utils/app_strings.dart';

/// Coupon apply/remove row for Pay & Collect / pre-payment.
class ResultPaymentCouponRow extends StatefulWidget {
  const ResultPaymentCouponRow({
    super.key,
    required this.appliedDiscount,
    required this.couponError,
    required this.busy,
    required this.onApply,
    required this.onUnapply,
  });

  final SessionDiscount? appliedDiscount;
  final String? couponError;
  final bool busy;
  final Future<void> Function(String code) onApply;
  final Future<void> Function() onUnapply;

  @override
  State<ResultPaymentCouponRow> createState() => _ResultPaymentCouponRowState();
}

class _ResultPaymentCouponRowState extends State<ResultPaymentCouponRow> {
  late final TextEditingController _codeCtrl;

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final applied = widget.appliedDiscount;
    final busy = widget.busy;

    if (applied != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${applied.code}: −${AppStrings.currencyRupee}${applied.discountAmount}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: busy ? null : () => widget.onUnapply(),
              child: Text(
                AppStrings.removeCoupon,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeCtrl,
                enabled: !busy,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: AppStrings.couponCodeLabel,
                  labelStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white),
                  ),
                ),
                textCapitalization: TextCapitalization.characters,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () => widget.onApply(_codeCtrl.text),
              child: const Text(AppStrings.applyCoupon),
            ),
          ],
        ),
        if ((widget.couponError ?? '').isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            widget.couponError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFFFCDD2), fontSize: 12),
          ),
        ],
      ],
    );
  }
}
