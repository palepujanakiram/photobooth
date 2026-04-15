import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors, Scaffold;
import 'package:flutter_zxing/flutter_zxing.dart';

import '../../utils/kiosk_qr_payload.dart';
import '../../views/widgets/app_colors.dart';

/// Booth camera scans the QR shown on the operator’s phone ([KioskCodeQr]), then links.
/// Pops with the kiosk code on success. Web stub only (no FFI camera scanner).
class KioskQrScanScreen extends StatefulWidget {
  const KioskQrScanScreen({super.key});

  @override
  State<KioskQrScanScreen> createState() => _KioskQrScanScreenState();
}

class _KioskQrScanScreenState extends State<KioskQrScanScreen> {
  bool _handled = false;

  void _onScan(Code? code) {
    if (_handled || code == null) return;
    final text = code.text;
    if (text == null || text.isEmpty) return;
    final kiosk = KioskQrPayload.parse(text);
    if (kiosk == null || kiosk.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop<String>(kiosk);
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);

    if (kIsWeb) {
      return CupertinoPageScaffold(
        backgroundColor: appColors.backgroundColor,
        navigationBar: CupertinoNavigationBar(
          backgroundColor: appColors.backgroundColor,
          leading: CupertinoNavigationBarBackButton(
            onPressed: () => Navigator.of(context).pop(),
          ),
          middle: Text(
            'Scan QR',
            style: TextStyle(color: appColors.textColor),
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'This device needs the booth app (Android or iOS) so the kiosk camera can scan the operator’s QR.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: appColors.secondaryTextColor,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          ReaderWidget(
            codeFormat: Format.qrCode,
            tryHarder: true,
            tryRotate: true,
            tryInverted: true,
            resolution: ResolutionPreset.high,
            scanDelay: const Duration(milliseconds: 400),
            scanDelaySuccess: const Duration(milliseconds: 800),
            cropPercent: 0.65,
            showGallery: true,
            showFlashlight: true,
            showToggleCamera: true,
            onScan: _onScan,
            onScanFailure: (_) {},
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(context).pop(),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.xmark,
                        color: CupertinoColors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Text(
                  'Aim this booth’s camera at the QR on the operator’s phone screen',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: CupertinoColors.white.withValues(alpha: 0.92),
                    fontSize: 15,
                    height: 1.35,
                    shadows: const [
                      Shadow(
                        blurRadius: 8,
                        color: Colors.black54,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
