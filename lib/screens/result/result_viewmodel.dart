import 'dart:ui';
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
  bool _isPrinting = false;
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
  bool get isPrinting => _isPrinting;
  bool get isSharing => _isSharing;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  String get printerIp => _printerIp;
  bool get isDownloading => _isDownloading;
  String get downloadMessage => _downloadMessage;
  String? get downloadError => _downloadError;

  bool get isRemoteImage {
    final path = _transformedImage?.imageFile.path;
    if (path == null) {
      return false;
    }
    return !kIsWeb && _isRemoteUrl(path);
  }

  bool get isRemoteImageUrl {
    final path = _transformedImage?.imageFile.path;
    if (path == null) {
      return false;
    }
    return _isRemoteUrl(path);
  }
  
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

  Future<void> ensureLocalImage() async {
    if (_transformedImage == null || _isDownloading) {
      return;
    }
    if (!isRemoteImage) {
      return;
    }

    _isDownloading = true;
    _downloadMessage = 'Downloading result...';
    _downloadError = null;
    notifyListeners();

    try {
      final imageFile = _transformedImage!.imageFile;
      final downloaded = await _apiService.downloadImageToTemp(
        imageFile.path,
        onProgress: (message) {
          _downloadMessage = message;
          notifyListeners();
        },
      );
      _transformedImage = _transformedImage!.copyWith(imageFile: downloaded);
    } catch (e) {
      _downloadError = 'Failed to download image: $e';
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  /// Prints the transformed image using system print dialog
  Future<void> printImage() async {
    if (_transformedImage == null) {
      _errorMessage = 'No image to print';
      notifyListeners();
      return;
    }
    if (isRemoteImage) {
      await ensureLocalImage();
      if (isRemoteImage) {
        _errorMessage = _downloadError ?? 'Image download failed';
        notifyListeners();
        return;
      }
    }

    _isPrinting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _printService.printImageWithDialog(_transformedImage!.imageFile);
    } on PrintException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to print: $e';
      notifyListeners();
    } finally {
      _isPrinting = false;
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
    if (isRemoteImage) {
      await ensureLocalImage();
      if (isRemoteImage) {
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

    _isPrinting = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _printService.printImageToNetworkPrinter(
        _transformedImage!.imageFile,
        printerIp: _printerIp,
      );
    } on PrintException catch (e) {
      _errorMessage = e.message;
      notifyListeners();
    } catch (e) {
      _errorMessage = 'Failed to print: $e';
      notifyListeners();
    } finally {
      _isPrinting = false;
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
    if (isRemoteImage) {
      await ensureLocalImage();
      if (isRemoteImage) {
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
        _transformedImage!.imageFile,
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
    if (isRemoteImage) {
      await ensureLocalImage();
      if (isRemoteImage) {
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
        _transformedImage!.imageFile,
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

  bool _isRemoteUrl(String path) {
    final lower = path.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }
}

