import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../../views/widgets/kiosk_payment_qr_display.dart';
import 'result_viewmodel.dart';

/// UPI QR slot on the Pay screen — listens to [ResultViewModel] directly so
/// payment fields repaint without relying on parent [Consumer] rebuild timing.
class ResultPaymentQrArea extends StatelessWidget {
  const ResultPaymentQrArea({
    super.key,
    required this.viewModel,
    required this.maxQrWidth,
    required this.onRetry,
  });

  final ResultViewModel viewModel;
  final double maxQrWidth;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) => _buildContent(viewModel),
    );
  }

  Widget _buildContent(ResultViewModel vm) {
    if (!vm.isPaymentGatewayEnabled) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Image.asset(
          'lib/images/upi_qr_fallback.png',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
      );
    }

    if (vm.hasPaymentQrPayload) {
      return KioskPaymentQrDisplay(
        key: ValueKey<String>(
          '${vm.qrImageUrl}|${vm.upiLink}|${vm.paymentLink}',
        ),
        qrImageUrl: vm.qrImageUrl,
        upiLink: vm.upiLink,
        paymentLink: vm.paymentLink,
        maxContentWidth: maxQrWidth,
      );
    }

    if (vm.paymentInitInProgress) {
      return const SizedBox(
        width: double.infinity,
        height: 280,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            CupertinoIcons.qrcode,
            size: 48,
            color: Colors.grey.shade600,
          ),
          const SizedBox(height: 10),
          Text(
            vm.paymentInitError ??
                'UPI QR is not ready yet. Tap Retry or ask staff.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: vm.paymentInitInProgress ? null : onRetry,
            child: const Text('Retry QR'),
          ),
        ],
      ),
    );
  }
}
