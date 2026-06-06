import 'package:flutter/material.dart';

import 'result_payment_status.dart';
import 'result_viewmodel.dart';

const TextStyle kResultPaymentBoxTitleStyle = TextStyle(
  fontSize: 26,
  fontWeight: FontWeight.bold,
  height: 1.15,
  color: Colors.white,
);

/// Payment card inner column (Sonar S3776 extraction from [ResultScreen]).
class ResultPaymentCardColumn extends StatelessWidget {
  const ResultPaymentCardColumn({
    super.key,
    required this.viewModel,
    required this.maxQrWidth,
    required this.refreshingPolling,
    required this.failureSecondsLeft,
    required this.onRefreshPolling,
    required this.onGetHelp,
    required this.refreshPollingChild,
    required this.buildQrArea,
  });

  final ResultViewModel viewModel;
  final double maxQrWidth;
  final bool refreshingPolling;
  final int failureSecondsLeft;
  final VoidCallback onRefreshPolling;
  final VoidCallback onGetHelp;
  final Widget refreshPollingChild;
  final Widget Function(ResultViewModel vm, double maxQrWidth) buildQrArea;

  @override
  Widget build(BuildContext context) {
    final status = ResultPaymentStatusPresentation.fromViewModel(viewModel);
    return Column(
      children: [
        const Text('Pay via UPI', style: kResultPaymentBoxTitleStyle),
        const SizedBox(height: 4),
        Text(
          '₹${viewModel.totalPrice}',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.2,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Center(
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: buildQrArea(viewModel, maxQrWidth),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          status.statusMessage,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: status.statusMessageColor,
          ),
        ),
        if (viewModel.isDeadPollingFallbackVisible) ...[
          const SizedBox(height: 10),
          Text(
            'Did your payment go through?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.95),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.35),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: refreshingPolling ? null : onRefreshPolling,
                  child: refreshPollingChild,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.16),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: onGetHelp,
                  child: const Text('Get help'),
                ),
              ),
            ],
          ),
        ],
        if (viewModel.fcmPaymentPushSuccess == false && failureSecondsLeft > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Returning to start in ${failureSecondsLeft}s',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.75),
            ),
          ),
        ],
      ],
    );
  }
}
