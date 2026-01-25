import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'transformed_image_model.dart';
import '../../services/api_service.dart';
import '../../services/print_service.dart';
import '../../services/share_service.dart';
import '../../utils/exceptions.dart';

class ResultViewModel extends ChangeNotifier {
  final PrintService _printService;
  final ShareService _shareService;
  final ApiService _apiService;
  TransformedImageModel? _transformedImage;
  final int? _transformationTime;
  bool _isDialogPrinting = false;
  bool _isSilentPrinting = false;
  bool _isSharing = false;
  String? _errorMessage;
  String _printerIp = '192.168.2.108'; // Default printer IP
  bool _isDownloading = false;
  String _downloadMessage = '';
  String? _downloadError;

  ResultViewModel({
    required TransformedImageModel transformedImage,
    int? transformationTime,
    PrintService? printService,
    ShareService? shareService,
    ApiService? apiService,
  })  : _transformedImage = transformedImage,
        _transformationTime = transformationTime,
        _printService = printService ?? PrintService(),
        _shareService = shareService ?? ShareService(),
        _apiService = apiService ?? ApiService();

  TransformedImageModel? get transformedImage => _transformedImage;
  int? get transformationTime => _transformationTime;
  bool get isDialogPrinting => _isDialogPrinting;
  bool get isSilentPrinting => _isSilentPrinting;
  bool get isPrinting => _isDialogPrinting || _isSilentPrinting;
  bool get isSharing => _isSharing;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  String get printerIp => _printerIp;
  bool get isDownloading => _isDownloading;
  String get downloadMessage => _downloadMessage;
  String? get downloadError => _downloadError;

  /// Image URL for display (always available)
  String? get imageUrl => _transformedImage?.imageUrl;

  /// Whether we have a local file (for share/print)
  bool get hasLocalFile => _transformedImage?.localFile != null;

  /// Whether we need to download for share/print (mobile only)
  bool get needsDownload => !kIsWeb && !hasLocalFile;

  String get formattedTransformationTime {
    if (_transformationTime == null) return '';
    final minutes = _transformationTime! ~/ 60;
    final seconds = _transformationTime! % 60;
    if (minutes > 0) {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
    return '${seconds}s';
  }

  /// Updates the printer IP address
  void setPrinterIp(String ip) {
    _printerIp = ip.trim();
    notifyListeners();
  }

  Future<void> ensureLocalFile() async {
    if (_transformedImage == null || _isDownloading || hasLocalFile) {
      return;
    }

    _isDownloading = true;
    _downloadMessage = 'Downloading result...';
    _downloadError = null;
    notifyListeners();

    try {
      final downloaded = await _apiService.downloadImageToTemp(
        _transformedImage!.imageUrl,
        onProgress: (message) {
          _downloadMessage = message;
          notifyListeners();
        },
      );
      _transformedImage = _transformedImage!.copyWith(localFile: downloaded);
    } catch (e) {
      _downloadError = 'Failed to download image: $e';
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  XFile? get _localFileForShare => _transformedImage?.localFile;

  /// Prints the transformed image using system print dialog
  Future<void> printImage() async {
    if (_transformedImage == null) {
      _errorMessage = 'No image to print';
      notifyListeners();
      return;
    }
    if (needsDownload) {
      await ensureLocalFile();
      if (needsDownload) {
        _errorMessage = _downloadError ?? 'Image download failed';
        notifyListeners();
        return;
      }
    }

    _isDialogPrinting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _printService.printImageWithDialog(_localFileForShare!);
    } on PrintException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to print: $e';
      notifyListeners();
    } finally {
      _isDialogPrinting = false;
      notifyListeners();
    }
  }

  /// Silently prints the transformed image to network printer
  Future<void> silentPrintToNetwork() async {
    if (_transformedImage == null) {
      _errorMessage = 'No image to print';
      notifyListeners();
      return;
    }
    if (needsDownload) {
      await ensureLocalFile();
      if (needsDownload) {
        _errorMessage = _downloadError ?? 'Image download failed';
        notifyListeners();
        return;
      }
    }

    if (_printerIp.isEmpty) {
      _errorMessage = 'Please enter a printer IP address';
      notifyListeners();
      return;
    }

    _isSilentPrinting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _printService.printImageToNetworkPrinter(
        _localFileForShare!,
        printerIp: _printerIp,
      );
    } on PrintException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to print: $e';
      notifyListeners();
    } finally {
      _isSilentPrinting = false;
      notifyListeners();
    }
  }

  /// Shares the transformed image
  Future<void> shareImage({String? text}) async {
    if (_transformedImage == null) {
      _errorMessage = 'No image to share';
      notifyListeners();
      return;
    }
    if (needsDownload) {
      await ensureLocalFile();
      if (needsDownload) {
        _errorMessage = _downloadError ?? 'Image download failed';
        notifyListeners();
        return;
      }
    }

    _isSharing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _shareService.shareImage(
        _localFileForShare!,
        text: text,
      );
    } on ShareException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to share: $e';
      notifyListeners();
    } finally {
      _isSharing = false;
      notifyListeners();
    }
  }

  /// Shares the transformed image via WhatsApp
  /// For iOS: Pass [sharePositionOrigin] to position the share sheet
  Future<void> shareViaWhatsApp({
    String? text,
    Rect? sharePositionOrigin,
  }) async {
    if (_transformedImage == null) {
      _errorMessage = 'No image to share';
      notifyListeners();
      return;
    }
    if (needsDownload) {
      await ensureLocalFile();
      if (needsDownload) {
        _errorMessage = _downloadError ?? 'Image download failed';
        notifyListeners();
        return;
      }
    }

    _isSharing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _shareService.shareViaWhatsApp(
        _localFileForShare!,
        text: text,
        sharePositionOrigin: sharePositionOrigin,
      );
    } on ShareException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to share via WhatsApp: $e';
      notifyListeners();
    } finally {
      _isSharing = false;
      notifyListeners();
    }
  }
}

