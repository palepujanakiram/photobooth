import 'package:flutter/material.dart';

import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import 'result_viewmodel.dart';

/// Stepper to choose physical print copies (1–[AppConstants.kMaxPrintCopies]).
class ResultPaymentCopiesRow extends StatelessWidget {
  const ResultPaymentCopiesRow({
    super.key,
    required this.viewModel,
  });

  final ResultViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final copies = viewModel.printCopies;
    final enabled = viewModel.canChangePrintCopies &&
        !viewModel.paymentInitInProgress &&
        !viewModel.couponBusy;
    final sheets = viewModel.printSheetCount;

    return Column(
      children: [
        Text(
          AppStrings.resultPrintCopiesLabel,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _CopyButton(
              icon: Icons.remove,
              onPressed: enabled && copies > AppConstants.kDefaultPrintCopies
                  ? () => viewModel.setPrintCopies(copies - 1)
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  Text(
                    '$copies',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                  Text(
                    AppStrings.resultPrintCopiesEach(copies),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            _CopyButton(
              icon: Icons.add,
              onPressed: enabled && copies < AppConstants.kMaxPrintCopies
                  ? () => viewModel.setPrintCopies(copies + 1)
                  : null,
            ),
          ],
        ),
        if (sheets > 0) ...[
          const SizedBox(height: 4),
          Text(
            AppStrings.resultPrintSheetsLine(sheets),
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ],
      ],
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: onPressed == null ? 0.06 : 0.14),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: onPressed == null ? 0.35 : 1),
            size: 22,
          ),
        ),
      ),
    );
  }
}
