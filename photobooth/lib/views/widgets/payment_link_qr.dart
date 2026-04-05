import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Renders [paymentLink] as a scannable QR code (ZXing on mobile/desktop, qr_flutter on web).
class PaymentLinkQr extends StatelessWidget {
  const PaymentLinkQr({
    super.key,
    required this.paymentLink,
    required this.size,
  });

  final String paymentLink;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return QrImageView(
        data: paymentLink,
        size: size,
        backgroundColor: Colors.white,
      );
    }

    // ZXing returns raw 1-channel matrix bytes, not PNG. Image.memory needs PNG (see WriterWidget in flutter_zxing).
    final w = size.round().clamp(64, 512);
    final h = size.round().clamp(64, 512);
    final encode = zx.encodeBarcode(
      contents: paymentLink,
      params: EncodeParams(
        format: Format.qrCode,
        width: w,
        height: h,
        margin: 2,
      ),
    );

    if (!encode.isValid || encode.data == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            encode.error ?? 'Could not create QR code',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ),
      );
    }

    try {
      final pngBytes = pngFromBytes(encode.data!, w, h);
      return Image.memory(
        pngBytes,
        width: size,
        height: size,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    } catch (e) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            e.toString(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ),
      );
    }
  }
}
