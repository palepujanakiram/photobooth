import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'payment_link_qr.dart';

/// Razorpay / UPI QR for the Pay screen — matches web kiosk priority in
/// `client/src/components/kiosk/cashfree-qr.tsx` (hosted PNG first).
///
/// Priority: [qrImageUrl] → [upiLink] → [paymentLink] (client-rendered QR).
class KioskPaymentQrDisplay extends StatelessWidget {
  const KioskPaymentQrDisplay({
    super.key,
    this.qrImageUrl,
    this.upiLink,
    this.paymentLink,
    this.maxContentWidth = 460,
  });

  final String? qrImageUrl;
  final String? upiLink;
  final String? paymentLink;

  /// Caps hosted PNG width so tall cards stay readable on narrow layouts.
  final double maxContentWidth;

  static const double _hostedMaxHeight = 500;
  static const double _clientQrSize = 300;

  @override
  Widget build(BuildContext context) {
    final hosted = qrImageUrl?.trim();
    if (hosted != null && hosted.isNotEmpty) {
      return _hostedRzpCard(context, hosted);
    }
    final upi = upiLink?.trim();
    if (upi != null && upi.isNotEmpty) {
      return _clientQr(upi);
    }
    final link = paymentLink?.trim();
    if (link != null && link.isNotEmpty) {
      return _clientQr(link);
    }
    return Icon(
      Icons.qr_code_2,
      size: 72,
      color: Colors.grey.shade600,
    );
  }

  Widget _clientQr(String data) {
    return PaymentLinkQr(
      paymentLink: data,
      size: _clientQrSize,
    );
  }

  Widget _hostedRzpCard(BuildContext context, String url) {
    final fallback = paymentLink?.trim();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = !constraints.hasBoundedHeight ||
                constraints.maxHeight.isInfinite
            ? _hostedMaxHeight
            : math.min(_hostedMaxHeight, constraints.maxHeight);
        final maxW = !constraints.hasBoundedWidth ||
                constraints.maxWidth.isInfinite
            ? maxContentWidth
            : math.min(maxContentWidth, constraints.maxWidth);
        return SizedBox(
          width: maxW,
          height: maxH,
          child: Center(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              filterQuality: FilterQuality.high,
              gaplessPlayback: true,
              webHtmlElementStrategy: kIsWeb
                  ? WebHtmlElementStrategy.prefer
                  : WebHtmlElementStrategy.never,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) {
                  return child;
                }
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                if (fallback != null && fallback.isNotEmpty) {
                  return PaymentLinkQr(
                    paymentLink: fallback,
                    size: _clientQrSize,
                  );
                }
                return SizedBox(
                  height: math.min(200, maxH),
                  width: double.infinity,
                  child: Icon(
                    Icons.broken_image_outlined,
                    size: 56,
                    color: Colors.grey.shade600,
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
