import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import '../photo_generate/photo_generate_viewmodel.dart';
import '../photo_capture/photo_model.dart';
import '../../services/api_service.dart';
import '../../services/app_settings_manager.dart';
import '../../services/print_service.dart';
import '../../services/session_manager.dart';
import '../../services/share_service.dart';
import '../../utils/constants.dart';
import '../../utils/exceptions.dart';

class ResultViewModel extends ChangeNotifier {
  final List<GeneratedImage> _generatedImages;
  final PhotoModel? _originalPhoto;
  final PrintService _printService;
  final ShareService _shareService;
  final ApiService _apiService;
  final SessionManager _sessionManager;
  final AppSettingsManager? _appSettingsManager;

  final bool _isProcessing = false;
  String? _errorMessage;
  String _printerHost;
  
  // Print/Share state
  bool _isSilentPrinting = false;
  bool _isDialogPrinting = false;
  bool _isSharing = false;
  bool _isDownloading = false;
  String _downloadMessage = '';
  
  // Track which action initiated the download
  String _downloadingForAction = ''; // 'silent', 'dialog', 'share'
  
  // Downloaded files for each image
  final Map<String, XFile> _downloadedFiles = {};

  ResultViewModel({
    required List<GeneratedImage> generatedImages,
    PhotoModel? originalPhoto,
    PrintService? printService,
    ShareService? shareService,
    ApiService? apiService,
    SessionManager? sessionManager,
    AppSettingsManager? appSettingsManager,
  })  : _generatedImages = generatedImages,
        _originalPhoto = originalPhoto,
        _printService = printService ?? PrintService(),
        _shareService = shareService ?? ShareService(),
        _apiService = apiService ?? ApiService(),
        _sessionManager = sessionManager ?? SessionManager(),
        _appSettingsManager = appSettingsManager,
        _printerHost = _defaultPrinterHost(appSettingsManager);

  List<GeneratedImage> get generatedImages => _generatedImages;
  PhotoModel? get originalPhoto => _originalPhoto;
  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  String get printerHost => _printerHost;

  static String _defaultPrinterHost(AppSettingsManager? manager) {
    final fromApi = manager?.settings?.printerHost?.trim();
    if (fromApi != null && fromApi.isNotEmpty) {
      return fromApi;
    }
    return AppConstants.kDefaultPrinterHost;
  }

  /// Port from `/api/settings` when valid; otherwise HTTP default (80).
  int get effectivePrinterPort {
    final p = _appSettingsManager?.settings?.printerPort;
    if (p != null && p > 0 && p <= 65535) {
      return p;
    }
    return 80;
  }

  int get initialPrintPrice =>
      _appSettingsManager?.settings?.initialPrice ??
      AppConstants.kDefaultInitialPrintPrice;

  int get additionalPrintPrice =>
      _appSettingsManager?.settings?.additionalPrintPrice ??
      AppConstants.kDefaultAdditionalPrintPrice;
  
  bool get isSilentPrinting => _isSilentPrinting;
  bool get isDialogPrinting => _isDialogPrinting;
  bool get isPrinting => _isSilentPrinting || _isDialogPrinting;
  bool get isSharing => _isSharing;
  bool get isDownloading => _isDownloading;
  String get downloadMessage => _downloadMessage;
  
  // Check if downloading for specific action
  bool get isDownloadingForSilentPrint => _isDownloading && _downloadingForAction == 'silent';
  bool get isDownloadingForDialogPrint => _isDownloading && _downloadingForAction == 'dialog';
  bool get isDownloadingForShare => _isDownloading && _downloadingForAction == 'share';

  /// Get total price based on number of photos
  int get totalPrice {
    if (_generatedImages.isEmpty) return 0;
    final basePrice = initialPrintPrice;
    final additionalPrice = additionalPrintPrice;
    return basePrice +
        (_generatedImages.length > 1
            ? (_generatedImages.length - 1) * additionalPrice
            : 0);
  }

  /// Updates the printer host (hostname or IP) shown in the print options field.
  void setPrinterHost(String host) {
    _printerHost = host.trim();
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Deletes the session on the server (DELETE /api/sessions/{sessionId}) and clears local session.
  /// Call after user confirms "Delete my photos". Throws [ApiException] on API failure.
  Future<void> deleteSession() async {
    final sessionId = _sessionManager.sessionId;
    if (sessionId == null) return;
    await _apiService.deleteSession(sessionId);
    _sessionManager.clearSession();
  }

  /// Download all images to temp files for print/share
  Future<bool> _ensureAllFilesDownloaded(String forAction) async {
    if (_isDownloading) return false;
    
    _isDownloading = true;
    _downloadingForAction = forAction;
    _downloadMessage = 'Preparing images...';
    notifyListeners();

    try {
      for (int i = 0; i < _generatedImages.length; i++) {
        final image = _generatedImages[i];
        if (!_downloadedFiles.containsKey(image.id)) {
          _downloadMessage = 'Downloading image ${i + 1} of ${_generatedImages.length}...';
          notifyListeners();
          
          final downloaded = await _apiService.downloadImageToTemp(
            image.imageUrl,
            onProgress: (message) {
              _downloadMessage = message;
              notifyListeners();
            },
          );
          _downloadedFiles[image.id] = downloaded;
        }
      }
      
      _isDownloading = false;
      _downloadingForAction = '';
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to download images: $e';
      _isDownloading = false;
      _downloadingForAction = '';
      notifyListeners();
      return false;
    }
  }

  /// Get downloaded files list
  List<XFile> get _downloadedFilesList {
    return _generatedImages
        .where((img) => _downloadedFiles.containsKey(img.id))
        .map((img) => _downloadedFiles[img.id]!)
        .toList();
  }

  /// Silent print all images to network printer
  Future<void> silentPrintToNetwork() async {
    if (_printerHost.isEmpty) {
      _errorMessage = 'Please enter a printer address';
      notifyListeners();
      return;
    }

    // Download files first if needed
    if (!kIsWeb && _downloadedFilesList.length != _generatedImages.length) {
      final success = await _ensureAllFilesDownloaded('silent');
      if (!success) return;
    }

    _isSilentPrinting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final files = _downloadedFilesList;
      for (int i = 0; i < files.length; i++) {
        await _printService.printImageToNetworkPrinter(
          files[i],
          printerHost: _printerHost,
          printerPort: effectivePrinterPort,
        );
      }
    } on PrintException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Failed to print: $e';
    } finally {
      _isSilentPrinting = false;
      notifyListeners();
    }
  }

  /// Print all images using system print dialog
  Future<void> printWithDialog() async {
    // Download files first if needed
    if (!kIsWeb && _downloadedFilesList.length != _generatedImages.length) {
      final success = await _ensureAllFilesDownloaded('dialog');
      if (!success) return;
    }

    _isDialogPrinting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final files = _downloadedFilesList;
      for (int i = 0; i < files.length; i++) {
        await _printService.printImageWithDialog(files[i]);
      }
    } on PrintException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Failed to print: $e';
    } finally {
      _isDialogPrinting = false;
      notifyListeners();
    }
  }

  /// Share all images
  Future<void> shareImages({Rect? sharePositionOrigin}) async {
    // Download files first if needed
    if (!kIsWeb && _downloadedFilesList.length != _generatedImages.length) {
      final success = await _ensureAllFilesDownloaded('share');
      if (!success) return;
    }

    _isSharing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final files = _downloadedFilesList;
      // Share all images using the multiple images method
      await _shareService.shareMultipleImages(
        files,
        text: 'Check out my ${files.length} AI generated photo${files.length > 1 ? 's' : ''}!',
        sharePositionOrigin: sharePositionOrigin,
      );
    } on ShareException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Failed to share: $e';
    } finally {
      _isSharing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    // Clean up downloaded files if needed
    super.dispose();
  }
}
