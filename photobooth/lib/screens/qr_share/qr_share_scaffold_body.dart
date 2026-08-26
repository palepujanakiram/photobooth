import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../utils/app_strings.dart';
import '../../views/widgets/delete_my_photos_action.dart';

/// Loaded QR share screen body (Sonar S3776 extraction from [QrShareScreen]).
class QrShareScaffoldBody extends StatelessWidget {
  const QrShareScaffoldBody({
    super.key,
    required this.qrData,
    required this.longUrl,
    required this.expiry,
    required this.headline,
    required this.waLine,
    required this.secondsLeftListenable,
    required this.onExit,
    this.offline = false,
    this.appBarTitle,
  });

  final String qrData;
  final String longUrl;
  final String expiry;
  final String headline;
  final String waLine;
  final ValueListenable<int> secondsLeftListenable;
  final VoidCallback onExit;
  final bool offline;
  final String? appBarTitle;

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
        title: Text(
          appBarTitle ?? 'SCAN & SHARE',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _QrShareStaticBackground()),
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
                        canShowQr || offline
                            ? headline
                            : AppStrings.qrSharePreparingShareLink,
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
                      _QrShareCodeBox(
                        canShowQr: canShowQr,
                        qrData: qrData,
                        offline: offline,
                      ),
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
                        secondsLeftListenable: secondsLeftListenable,
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
  const _QrShareCodeBox({
    required this.canShowQr,
    required this.qrData,
    this.offline = false,
  });

  final bool canShowQr;
  final String qrData;
  final bool offline;

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
          ? RepaintBoundary(
              child: QrImageView(
                key: ValueKey<String>(qrData),
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
              ),
            )
          : Center(
              child: offline
                  ? Icon(
                      Icons.print_outlined,
                      size: 72,
                      color: Colors.grey.shade500,
                    )
                  : const CircularProgressIndicator(strokeWidth: 2),
            ),
    );
  }
}

/// Start-again CTA + idle countdown (print/share actions removed — no reliable
/// printer acknowledgement, and guests should leave via QR / Start again).
/// Lightweight gradient — avoids blur, network image, and starfield animation
/// on a screen that must stay responsive during background DNP printing.
class _QrShareStaticBackground extends StatelessWidget {
  const _QrShareStaticBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0D2130),
            Color(0xFF0A1628),
            Color(0xFF050810),
          ],
        ),
      ),
    );
  }
}

class _QrShareFooter extends StatelessWidget {
  const _QrShareFooter({
    required this.secondsLeftListenable,
    required this.onStartAgain,
  });

  final ValueListenable<int> secondsLeftListenable;
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
        ValueListenableBuilder<int>(
          valueListenable: secondsLeftListenable,
          builder: (context, secondsLeft, _) {
            return Text(
              AppStrings.qrShareResettingIn(secondsLeft),
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            );
          },
        ),
        const DeleteMyPhotosButton(compact: true),
      ],
    );
  }
}
