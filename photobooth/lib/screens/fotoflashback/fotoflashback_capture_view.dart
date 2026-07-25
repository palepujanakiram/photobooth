import 'dart:async';

import 'package:flutter/material.dart';

import '../../utils/fotoflashback_navigation.dart';
import '../../utils/route_args.dart';
import '../../views/widgets/app_colors.dart';

/// Compatibility route: forwards to multi-shot POSE (same screen for all 4).
class FotoFlashbackCaptureScreen extends StatefulWidget {
  const FotoFlashbackCaptureScreen({super.key});

  @override
  State<FotoFlashbackCaptureScreen> createState() =>
      _FotoFlashbackCaptureScreenState();
}

class _FotoFlashbackCaptureScreenState extends State<FotoFlashbackCaptureScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = FlashbackCaptureArgs.tryParse(
      ModalRoute.of(context)?.settings.arguments,
    );
    if (args == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        navigateToFotoFlashbackCapture(
          context: context,
          theme: args.theme,
          replace: true,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppColors.of(context);
    return Scaffold(
      backgroundColor: appColors.backgroundColor,
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}
