import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../photo_generate/photo_generate_viewmodel.dart';
import '../photo_capture/photo_model.dart';
import '../../services/api_service.dart';
import '../../services/customer_session_lifecycle.dart';
import '../../services/customer_data_deletion.dart';
import '../../services/app_settings_manager.dart';
import '../../services/file_helper.dart';
import '../../services/print_service.dart';
import '../../services/session_manager.dart';
import '../../services/share_service.dart';
import '../../services/kiosk_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/exceptions.dart';
import '../../utils/logger.dart';
import '../../utils/print_orientation.dart';
import '../../services/error_reporting/error_reporting_manager.dart';
import '../../services/fcm_service.dart';
import '../../services/payment_push_coordinator.dart';
import '../../services/whatsapp_push_coordinator.dart';
import '../../models/kiosk_share_link_model.dart';
import 'kiosk_receipt_share_fallback.dart';
import 'result_viewmodel_share_helpers.dart';

part 'result_viewmodel_impl.part.dart';

enum _PollVerdict { approved, failed, pending }

/// Outcome of the post-payment receipt POST, derived from the backend's
/// `{ whatsappQueued, whatsappSkipReason, pdfError, ... }` response.
///
/// Drives the one-shot UX toast on the QR share screen.
enum PostReceiptOutcome {
  /// Receipt POST hasn't completed yet (or not started). UI shows nothing.
  pending,

  /// Receipt POST never returned a usable response (after retries). Already
  /// reported to Bugsnag in [ResultViewModel._postSessionReceiptWithRetry].
  receiptFailed,

  /// WhatsApp queued + PDF OK + share URL ready. Silent success.
  allOk,

  /// WhatsApp queued, but PDF generation failed server-side.
  /// → "Message sent — receipt is delayed."
  whatsappOkPdfFailed,

  /// WhatsApp not queued because the customer didn't opt in (or didn't enter a
  /// number). Silent — by design.
  whatsappSkippedOptOut,

  /// WhatsApp not queued because the backend rejected the phone (E.164 valid
  /// at the client but backend's stricter check failed).
  /// → "That number didn't work" + QR fallback.
  whatsappSkippedInvalidPhone,

  /// WhatsApp not queued because the backend never received a phone number.
  /// → "No number entered" + QR fallback.
  whatsappSkippedNoPhone,
}

class ResultViewModel extends ChangeNotifier with _ResultViewModelImpl {
  final List<GeneratedImage> _generatedImages;
  final PhotoModel? _originalPhoto;
  final PrintOrientation _printOrientation;
  final PrintService _printService;
  final ShareService _shareService;
  final ApiService _apiService;
  final SessionManager _sessionManager;
  final AppSettingsManager? _appSettingsManager;
  final KioskManager _kioskManager;

  final String? _customerName;
  final String? _customerPhone;
  final bool _customerWhatsappOptIn;

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

  String? _paymentLink;
  String? _qrImageUrl;
  String? _upiLink;
  String? _paymentInitError;
  bool _paymentInitInProgress = false;

  /// Set when an FCM payment push is handled on the Pay & Collect screen (inline UI, no dialog).
  String? _fcmPaymentStatusDetail;
  bool? _fcmPaymentPushSuccess;

  /// Server payment id from initiate; used to poll when FCM is missing (emulator / tray only).
  String? _activePaymentId;
  Timer? _paymentIdPollTimer;
  Timer? _sessionPollTimer;
  int _paymentIdPollTicks = 0;
  int _sessionPollTicks = 0;
  int _paymentIdNullStreak = 0;
  int _sessionNullStreak = 0;
  int _paymentIdConsecutiveFailureTicks = 0;
  int _sessionConsecutiveFailureTicks = 0;
  bool _paymentOutcomeHandled = false;

  bool _postPaymentSharePrepared = false;
  Future<void>? _postPaymentInflight;
  String? _receiptShareUrl;
  String? _receiptShareLongUrl;
  DateTime? _receiptShareExpiresAt;
  String? _kioskFallbackShareUrl;
  String? _kioskFallbackShareLongUrl;
  DateTime? _kioskFallbackShareExpiresAt;
  String? _receiptPdfUrl;
  bool _whatsappQueued = false;

  /// Server-emitted skip reason ("opted_out" / "no_phone" / "invalid_phone")
  /// when [whatsappQueued] is false. Null when queued or when backend didn't
  /// say.
  String? _whatsappSkipReason;

  /// Server-emitted PDF generation error string. Null on success.
  String? _pdfError;

  /// Set true once the receipt POST returns a non-null body. Distinguishes
  /// "WhatsApp not queued because server said so" from "we never got a server
  /// response at all (retries exhausted)".
  bool _receiptResponseReceived = false;

  String? _whatsappDeliveryStatus;
  String? _whatsappDeliveryDetail;
  Timer? _whatsappPollTimer;
  int _whatsappPollTicks = 0;

  /// Set true in [dispose]. All post-await callbacks should bail out before
  /// mutating state once this flips. [notifyListeners] is also overridden to
  /// be a safe no-op after dispose, so existing call sites don't need
  /// individual guards (they just become harmless).
  bool _disposed = false;
  bool get isDisposed => _disposed;

  String? get paymentLink => _paymentLink;
  String? get qrImageUrl => _qrImageUrl;
  String? get upiLink => _upiLink;
  String? get paymentInitError => _paymentInitError;
  bool get paymentInitInProgress => _paymentInitInProgress;

  String? get fcmPaymentStatusDetail => _fcmPaymentStatusDetail;
  bool? get fcmPaymentPushSuccess => _fcmPaymentPushSuccess;

  /// Client-only UX fallback: polling appears "stuck" (consecutive failures)
  /// for roughly 30 seconds on both payment status and session polling.
  bool get isDeadPollingFallbackVisible {
    if (_paymentOutcomeHandled) return false;
    if (_fcmPaymentPushSuccess != null) return false;
    // Poll interval is 3s; 10 consecutive failures ≈ 30s.
    return _paymentIdConsecutiveFailureTicks >= 10 &&
        _sessionConsecutiveFailureTicks >= 10;
  }

  bool get hasFcmPaymentStatus =>
      _fcmPaymentStatusDetail != null && _fcmPaymentStatusDetail!.isNotEmpty;

  String? get customerName => _customerName;
  String? get customerPhone => _customerPhone;
  bool get customerWhatsappOptIn => _customerWhatsappOptIn;

  /// WhatsApp queue is only meaningful when a phone exists and the user opted in.
  bool get effectiveWhatsappOptIn {
    final p = _customerPhone?.trim() ?? '';
    return p.isNotEmpty && _customerWhatsappOptIn;
  }

  String? get receiptShareUrl => _receiptShareUrl;
  String? get receiptShareLongUrl => _receiptShareLongUrl;
  DateTime? get receiptShareExpiresAt => _receiptShareExpiresAt;
  String? get kioskFallbackShareUrl => _kioskFallbackShareUrl;
  String? get kioskFallbackShareLongUrl => _kioskFallbackShareLongUrl;
  DateTime? get kioskFallbackShareExpiresAt => _kioskFallbackShareExpiresAt;
  String? get receiptPdfUrl => _receiptPdfUrl;
  bool get whatsappQueued => _whatsappQueued;
  String? get whatsappSkipReason => _whatsappSkipReason;
  String? get pdfError => _pdfError;

  /// Computed UX outcome the QR share screen uses to pick a toast.
  /// Stays [PostReceiptOutcome.pending] until the receipt POST completes.
  PostReceiptOutcome get postReceiptOutcome {
    if (!_postPaymentSharePrepared) return PostReceiptOutcome.pending;
    if (!_receiptResponseReceived) return PostReceiptOutcome.receiptFailed;

    if (_whatsappQueued) {
      if ((_pdfError ?? '').trim().isNotEmpty) {
        return PostReceiptOutcome.whatsappOkPdfFailed;
      }
      return PostReceiptOutcome.allOk;
    }

    // WhatsApp not queued — branch on server-supplied skip reason.
    switch ((_whatsappSkipReason ?? '').toLowerCase()) {
      case 'invalid_phone':
        return PostReceiptOutcome.whatsappSkippedInvalidPhone;
      case 'no_phone':
        return PostReceiptOutcome.whatsappSkippedNoPhone;
      case 'opted_out':
        return PostReceiptOutcome.whatsappSkippedOptOut;
      default:
        // Server didn't say. Fall back to client opt-in state: if the user
        // never opted in, treat as opted_out (silent). Otherwise treat as
        // success (PDF + share URL still useful).
        if (!effectiveWhatsappOptIn) {
          return PostReceiptOutcome.whatsappSkippedOptOut;
        }
        return PostReceiptOutcome.allOk;
    }
  }

  String? get whatsappDeliveryStatus => _whatsappDeliveryStatus;
  String? get whatsappDeliveryDetail => _whatsappDeliveryDetail;

  ResultViewModel({
    required List<GeneratedImage> generatedImages,
    PhotoModel? originalPhoto,
    PrintOrientation printOrientation = PrintOrientation.portrait,
    PrintService? printService,
    ShareService? shareService,
    ApiService? apiService,
    SessionManager? sessionManager,
    AppSettingsManager? appSettingsManager,
    KioskManager? kioskManager,
    String? customerName,
    String? customerPhone,
    bool customerWhatsappOptIn = false,
  })  : _generatedImages = generatedImages,
        _originalPhoto = originalPhoto,
        _printOrientation = printOrientation,
        _printService = printService ?? PrintService(),
        _shareService = shareService ?? ShareService(),
        _apiService = apiService ?? ApiService(),
        _sessionManager = sessionManager ?? SessionManager(),
        _appSettingsManager = appSettingsManager,
        _kioskManager = kioskManager ?? KioskManager(),
        _customerName = customerName,
        _customerPhone = customerPhone,
        _customerWhatsappOptIn = customerWhatsappOptIn,
        _printerHost = _defaultPrinterHost(appSettingsManager);

  List<GeneratedImage> get generatedImages => _generatedImages;
  PhotoModel? get originalPhoto => _originalPhoto;
  PrintOrientation get printOrientation => _printOrientation;
  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;
  bool get hasError => _errorMessage != null;
  String get printerHost => _printerHost;
  bool get isPaymentGatewayEnabled =>
      _appSettingsManager?.settings?.paymentGatewayEnabled ?? true;

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
  bool get isDownloadingForSilentPrint =>
      _isDownloading && _downloadingForAction == 'silent';
  bool get isDownloadingForDialogPrint =>
      _isDownloading && _downloadingForAction == 'dialog';
  bool get isDownloadingForShare =>
      _isDownloading && _downloadingForAction == 'share';

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

  /// Maps the 6 canonical statuses to short, customer-facing labels. Anything
  /// unrecognized falls through to a generic "Updating…" so a stray value
  /// doesn't leak raw enum strings into the UI.
  static String friendlyWhatsappStatus(String? raw) {
    final upper = (raw ?? '').trim().toUpperCase();
    switch (upper) {
      case 'PENDING':
        return 'Queued';
      case 'SENT':
        return 'Sending…';
      case 'DELIVERED':
        return 'Delivered';
      case 'READ':
        return 'Read';
      case 'FAILED':
        return "Couldn't deliver";
      case 'SKIPPED':
        return 'Skipped';
      default:
        return 'Updating…';
    }
  }

  /// No-op once [_disposed] flips — keeps callers that resolve a Future after
  /// the screen has navigated away from triggering "A ChangeNotifier was used
  /// after being disposed" assertions in debug.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _paymentIdPollTimer?.cancel();
    _sessionPollTimer?.cancel();
    stopWhatsappDeliveryPolling();
    super.dispose();
  }
}
