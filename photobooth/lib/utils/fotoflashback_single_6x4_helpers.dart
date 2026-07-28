import 'package:flutter/material.dart';

import '../models/strip_models.dart';
import '../screens/photo_generate/photo_generate_viewmodel.dart';
import '../screens/theme_selection/theme_model.dart';
import '../services/api_service.dart';
import '../services/session_manager.dart';
import '../utils/app_strings.dart';
import '../utils/constants.dart';
import '../utils/exceptions.dart';
import '../utils/fotoflashback_payment_helpers.dart';
import '../utils/logger.dart';

/// Compose one Classic still as landscape 6×4 and open print selection.
Future<String?> finishClassicSingle6x4({
  required BuildContext context,
  required ThemeModel theme,
  required String imageDataUrl,
  ApiService? api,
  SessionManager? sessionManager,
}) async {
  final sessionId =
      (sessionManager ?? SessionManager()).sessionId?.trim() ?? '';
  if (sessionId.isEmpty) {
    return AppStrings.sessionPhotoSyncNoSession;
  }

  try {
    final result = await (api ?? ApiService()).composeStrip(
      sessionId: sessionId,
      images: [imageDataUrl],
      filter: kDefaultStripFilterId,
      frame: kDefaultStripFrameId,
    );
    if (!context.mounted) return AppStrings.flashbackComposeFailed;

    final image = GeneratedImage(
      id: 'classic6x4_${DateTime.now().millisecondsSinceEpoch}',
      imageUrl: result.printImageUrl,
      theme: theme,
      isSelected: true,
    ).copyWith(
      printSize: result.printSize.isNotEmpty
          ? result.printSize
          : AppConstants.kPrintSizeLandscape6x4,
    );

    await navigateToFlashbackPrintSelection(
      context: context,
      image: image,
      printSize: result.printSize.isNotEmpty
          ? result.printSize
          : AppConstants.kPrintSizeLandscape6x4,
      transformationRunId: result.runId,
    );
    return null;
  } on ApiException catch (e) {
    AppLogger.error('Classic single 6×4 compose failed', error: e);
    return e.message;
  } catch (e, st) {
    AppLogger.error(
      'Classic single 6×4 compose failed',
      error: e,
      stackTrace: st,
    );
    return AppStrings.flashbackComposeFailed;
  }
}
