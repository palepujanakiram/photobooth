import 'package:flutter/foundation.dart';

import '../photo_generate/photo_generate_viewmodel.dart';
import '../../services/app_settings_manager.dart';
import '../../services/print_selection_coordinator.dart';
import '../../utils/constants.dart';
import '../../utils/payment_workflow_helpers.dart';

/// State for the post-Classic / post-AI print selection hub.
class PrintSelectionViewModel extends ChangeNotifier {
  PrintSelectionViewModel({
    required List<GeneratedImage> images,
    this.stripPrintSize,
    this.transformationRunId,
    AppSettingsManager? appSettingsManager,
    PrintSelectionCoordinator? coordinator,
  })  : _images = List<GeneratedImage>.from(images),
        _appSettings = appSettingsManager ?? AppSettingsManager(),
        _coordinator = coordinator ?? PrintSelectionCoordinator.instance {
    _syncCoordinator();
  }

  final AppSettingsManager _appSettings;
  final PrintSelectionCoordinator _coordinator;
  final String? stripPrintSize;
  final String? transformationRunId;

  List<GeneratedImage> _images;
  List<GeneratedImage> get images => List.unmodifiable(_images);

  List<GeneratedImage> get selectedImages =>
      _images.where((e) => e.isSelected).toList(growable: false);

  int get selectedCount => selectedImages.length;

  bool get canContinue => selectedCount > 0;

  bool get fromClassicStrip => _coordinator.fromClassicStrip;

  int get initialPrintPrice =>
      _appSettings.settings?.initialPrice ??
      AppConstants.kDefaultInitialPrintPrice;

  int get additionalPrintPrice =>
      _appSettings.settings?.additionalPrintPrice ??
      AppConstants.kDefaultAdditionalPrintPrice;

  /// Strip at base + each extra selected sheet at additional-copy price.
  int get selectedTotalPrice {
    final sheets = resolvePrintSheetCount(imageCount: selectedCount);
    if (sheets <= 0) return 0;
    return initialPrintPrice +
        (sheets > 1 ? (sheets - 1) * additionalPrintPrice : 0);
  }

  bool isStripImage(GeneratedImage image) {
    final size = image.printSize?.trim() ?? '';
    return size == AppConstants.kPrintSizeStripDual2x6;
  }

  /// Classic 1-shot 4×6 / 6×4 sheet (not a dual strip).
  bool isClassicSingleSheet(GeneratedImage image) {
    final size = image.printSize?.trim() ?? '';
    return size == AppConstants.kPrintSizePortrait4x6 ||
        size == AppConstants.kPrintSizeLandscape6x4;
  }

  /// Primary Classic deliverable — stays selected when it is the only sheet.
  bool isClassicDeliverable(GeneratedImage image) =>
      isStripImage(image) || isClassicSingleSheet(image);

  void toggleSelected(String id) {
    final i = _images.indexWhere((e) => e.id == id);
    if (i < 0) return;
    final img = _images[i];
    // Classic deliverable stays selected when it is the only sheet.
    if (isClassicDeliverable(img) && img.isSelected && selectedCount <= 1) {
      return;
    }
    _images[i] = img.copyWith(isSelected: !img.isSelected);
    _syncCoordinator();
    notifyListeners();
  }

  void reloadFromCoordinator() {
    _images = List<GeneratedImage>.from(_coordinator.images);
    notifyListeners();
  }

  void _syncCoordinator() {
    _coordinator.replaceImages(_images);
  }
}
