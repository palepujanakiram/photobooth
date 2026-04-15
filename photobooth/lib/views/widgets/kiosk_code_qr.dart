import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../utils/kiosk_qr_payload.dart';

/// Displays a scannable QR for the current kiosk code (e.g. on a phone for the booth to scan).
class KioskCodeQr extends StatelessWidget {
  const KioskCodeQr({
    super.key,
    required this.kioskCode,
    required this.size,
  });

  final String kioskCode;
  final double size;

  @override
  Widget build(BuildContext context) {
    final data = KioskQrPayload.encode(kioskCode);
    if (data.isEmpty) {
      return SizedBox(width: size, height: size);
    }
    return QrImageView(
      data: data,
      size: size,
      backgroundColor: Colors.white,
      errorStateBuilder: (ctx, err) => SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            err.toString(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ),
      ),
    );
  }
}
