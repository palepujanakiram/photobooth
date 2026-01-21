import 'package:flutter/foundation.dart';
import 'transformed_image_model.dart';
import '../../services/print_service.dart';
import '../../services/share_service.dart';
import '../../utils/exceptions.dart';

class ResultViewModel extends ChangeNotifier {
  final PrintService _printService;
  final ShareService _shareService;
  final TransformedImageModel? _transformedImage;
  bool _isPrinting = false;
  bool _isSharing = false;
  String? _errorMessage;
  String _printerIp = '192.168.2.108'; // Default printer IP

  ResultViewModel({
    required TransformedImageModel transformedImage,
    PrintService? printService,
    ShareService? shareService,
  })  : _transformedImage = transformedImage,
        _printService = printService ?? PrintService(),
        _shareService = shareService ?? ShareService();

  TransformedImageModel? get transformedImage => _transformedImage;
  bool get isPrinting => _isPrinting;
  bool get isSharing => _isSharing;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  String get printerIp => _printerIp;

  /// Updates the printer IP address
  void setPrinterIp(String ip) {
    _printerIp = ip.trim();
    notifyListeners();
  }

  /// Prints the transformed image using system print dialog
  Future<void> printImage() async {
    if (_transformedImage == null) {
      _errorMessage = 'No image to print';
      notifyListeners();
      return;
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
  Future<void> shareViaWhatsApp({String? text}) async {
    if (_transformedImage == null) {
      _errorMessage = 'No image to share';
      notifyListeners();
      return;
    }

    _isSharing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _shareService.shareViaWhatsApp(
        _transformedImage!.imageFile,
        text: text,
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

