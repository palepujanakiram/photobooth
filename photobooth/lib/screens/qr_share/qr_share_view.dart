import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/app_settings_manager.dart';
import '../../utils/constants.dart';
import '../../utils/logger.dart';
import '../../utils/route_args.dart';
import '../../views/widgets/app_colors.dart';
import '../../views/widgets/app_snackbar.dart';
import '../../views/widgets/theme_background.dart';
import '../result/result_viewmodel.dart';

class QrShareScreen extends StatefulWidget {
  const QrShareScreen({super.key});

  @override
  State<QrShareScreen> createState() => _QrShareScreenState();
}

class _QrShareScreenState extends State<QrShareScreen> {
  ResultViewModel? _viewModel;
  bool _initialized = false;
  Timer? _timer;
  int _secondsLeft = 60;
  bool _exiting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    final parsed =
        QrShareArgs.tryParse(ModalRoute.of(context)?.settings.arguments);
    if (parsed == null) return;

    _viewModel = ResultViewModel(
      generatedImages: parsed.generatedImages,
      originalPhoto: parsed.originalPhoto,
      appSettingsManager: context.read<AppSettingsManager>(),
    );
    _initialized = true;

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        t.cancel();
        unawaited(_exitToStart());
        return;
      }
      setState(() => _secondsLeft -= 1);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _viewModel?.dispose();
    super.dispose();
  }

  Future<void> _exitToStart() async {
    if (!mounted || _exiting) return;
    _exiting = true;
    _timer?.cancel();
    try {
      await _viewModel?.privacyWipeLocal();
    } catch (e, st) {
      AppLogger.debug('Privacy wipe (qr-share) failed: $e\n$st');
    }
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppConstants.kRouteTerms,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    final parsed = QrShareArgs.tryParse(ModalRoute.of(context)?.settings.arguments);
    final shareUrl = (parsed?.shareUrl ?? '').trim();
    final longUrl = (parsed?.shareLongUrl ?? '').trim();
    final expiresAt = parsed?.shareExpiresAt;

    if (!_initialized || _viewModel == null || parsed == null) {
      return Scaffold(
        backgroundColor: appColors.backgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    String expiryText() {
      if (expiresAt == null) return '';
      final local = expiresAt.toLocal();
      final hh = local.hour.toString().padLeft(2, '0');
      final mm = local.minute.toString().padLeft(2, '0');
      return 'Link expires at $hh:$mm';
    }

    return ChangeNotifierProvider.value(
      value: _viewModel!,
      child: Consumer<ResultViewModel>(
        builder: (context, viewModel, _) {
          final canShowQr = shareUrl.isNotEmpty;
          final expiry = expiryText();
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
                onPressed: _exitToStart,
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
                              canShowQr
                                  ? 'Scan this QR on your phone to download and share.'
                                  : 'Preparing your share link…',
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
                            const SizedBox(height: 14),
                            Container(
                              width: 280,
                              height: 280,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.6),
                                ),
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
                                      data: shareUrl,
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
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
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
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blueGrey.shade800,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size.fromHeight(52),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: viewModel.isPrinting
                                        ? null
                                        : () async {
                                            final messenger =
                                                ScaffoldMessenger.of(context);
                                            await viewModel.silentPrintToNetwork();
                                            if (!mounted) return;
                                            if (viewModel.hasError) {
                                              AppSnackBar.showError(
                                                messenger.context,
                                                viewModel.errorMessage ?? 'Print failed',
                                              );
                                            } else {
                                              AppSnackBar.showSuccess(
                                                messenger.context,
                                                'Print job sent!',
                                              );
                                            }
                                          },
                                    child: Text(
                                      viewModel.isPrinting ? 'Printing…' : 'Print again',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size.fromHeight(52),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: viewModel.isSharing
                                        ? null
                                        : () async {
                                            final messenger =
                                                ScaffoldMessenger.of(context);
                                            await viewModel.shareImages();
                                            if (!mounted) return;
                                            if (viewModel.hasError) {
                                              AppSnackBar.showError(
                                                messenger.context,
                                                viewModel.errorMessage ?? 'Share failed',
                                              );
                                            }
                                          },
                                    child: Text(
                                      viewModel.isSharing ? 'Sharing…' : 'Share (kiosk)',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Resetting in ${_secondsLeft}s',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
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
        },
      ),
    );
  }
}

