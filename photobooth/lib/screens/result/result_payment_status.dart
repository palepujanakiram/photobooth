import 'package:flutter/material.dart';
import 'result_viewmodel.dart';

/// User-facing status line and color under the UPI QR on [ResultScreen].
///
/// Encapsulates the previous nested ternaries for FCM/polling payment state.
class ResultPaymentStatusPresentation {
  const ResultPaymentStatusPresentation({
    required this.statusMessage,
    required this.statusMessageColor,
  });

  final String statusMessage;
  final Color statusMessageColor;

  /// Maps [ResultViewModel.fcmPaymentPushSuccess] and gateway flags to copy + color.
  static ResultPaymentStatusPresentation fromViewModel(ResultViewModel viewModel) {
    final paymentSucceeded = viewModel.fcmPaymentPushSuccess == true;
    final paymentFailed = viewModel.fcmPaymentPushSuccess == false;

    if (paymentFailed) {
      return ResultPaymentStatusPresentation(
        statusMessage:
            'Payment failed. Please try again.\nYou will return to start automatically.',
        statusMessageColor: Colors.red.shade200,
      );
    }
    if (paymentSucceeded) {
      return ResultPaymentStatusPresentation(
        statusMessage: 'Payment confirmed. Printing...',
        statusMessageColor: Colors.green.shade200,
      );
    }
    final waitingMessage = viewModel.isPaymentGatewayEnabled
        ? 'Waiting for payment confirmation...'
        : 'Waiting for admin approval...';
    return ResultPaymentStatusPresentation(
      statusMessage: waitingMessage,
      statusMessageColor: Colors.white.withValues(alpha: 0.85),
    );
  }
}

/// Height of the Pay & Collect card from [LayoutBuilder] constraints.
///
/// Uses at least 260px; expands up to parent height when bounded (tablets / landscape).
double computePaymentCardHeight(BoxConstraints outerConstraints) {
  const minimumCardHeight = 260.0;
  const fallbackCardHeight = 420.0;
  final maxHeight = outerConstraints.maxHeight;
  if (maxHeight.isFinite && maxHeight > 0) {
    return maxHeight.clamp(minimumCardHeight, 2000.0);
  }
  return fallbackCardHeight;
}
