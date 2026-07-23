import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../utils/app_strings.dart';
import '../../views/widgets/delete_my_photos_action.dart';
import '../../views/widgets/theme_background.dart';

/// Loaded QR share screen body (Sonar S3776 extraction from [QrShareScreen]).
class QrShareScaffoldBody extends StatelessWidget {
  const QrShareScaffoldBody({
    super.key,
    required this.qrData,
    required this.longUrl,
    required this.expiry,
    required this.headline,
    required this.waLine,
    required this.secondsLeft,
    required this.onExit,
  });

  final String qrData;
  final String longUrl;
  final String expiry;
  final String headline;
  final String waLine;
  final int secondsLeft;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final canShowQr = qrData.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        forceMaterialTransparency: true,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
          onPressed: onExit,
        ),
        title: const Text(
          'SCAN & SHARE',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: ThemeBackground()),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        canShowQr ? headline : 'Preparing your share link…',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: Colors.white.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (expiry.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          expiry,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.25,
                            color: Colors.white.withValues(alpha: 0.78),
                          ),
                        ),
                      ],
                      if (waLine.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          waLine,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.25,
                            color: Colors.white.withValues(alpha: 0.78),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _QrShareCodeBox(canShowQr: canShowQr, qrData: qrData),
                      if (longUrl.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SelectableText(
                          longUrl,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.25,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _QrShareFooter(
                        secondsLeft: secondsLeft,
                        onStartAgain: onExit,
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

class _QrShareCodeBox extends StatelessWidget {
  const _QrShareCodeBox({required this.canShowQr, required this.qrData});

  final bool canShowQr;
  final String qrData;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      height: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: canShowQr
          ? QrImageView(
              data: qrData,
              backgroundColor: Colors.white,
              errorStateBuilder: (ctx, err) => Center(
                child: Text(
                  err.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            )
          : const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
    );
  }
}

/// Start-again CTA + idle countdown (print/share actions removed — no reliable
/// printer acknowledgement, and guests should leave via QR / Start again).
class _QrShareFooter extends StatelessWidget {
  const _QrShareFooter({
    required this.secondsLeft,
    required this.onStartAgain,
  });

  final int secondsLeft;
  final VoidCallback onStartAgain;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              foregroundColor: Colors.white,
              elevation: 0,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: onStartAgain,
            child: const Text(AppStrings.qrShareStartAgain),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          AppStrings.qrShareResettingIn(secondsLeft),
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        const DeleteMyPhotosButton(compact: true),
      ],
    );
  }
}
