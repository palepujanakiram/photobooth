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
import '../../services/print_file.dart';
import '../../services/print_service_helpers.dart';
import '../../services/receipt_printer_service.dart';
import '../../services/session_manager.dart';
import '../../models/session_print_receipt_result.dart';
import '../../services/share_service.dart';
import '../../services/kiosk_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/exceptions.dart';
import '../../utils/logger.dart';
import '../../utils/payment_workflow_helpers.dart' as payment_workflow;
import '../../utils/print_orientation.dart';
import '../../utils/print_progress_helpers.dart';
import '../../utils/printer_endpoint.dart';
import '../../utils/error_reporting_helpers.dart';
import '../../services/error_reporting/error_reporting_manager.dart';
import '../../services/fcm_service.dart';
import '../../services/payment_push_coordinator.dart';
import '../../services/whatsapp_push_coordinator.dart';
import '../../models/customer_contact_capture.dart';
import '../../models/kiosk_share_link_model.dart';
import '../../models/session_discount.dart';
import '../../models/payment_initiate_result.dart';
import 'kiosk_receipt_share_fallback.dart';
import 'result_payment_poll_helpers.dart';
import 'result_viewmodel_share_helpers.dart';

part 'result_viewmodel_impl.part.dart';

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
  final ReceiptPrinterService _receiptPrinterService;

  final CustomerContactCapture _contact;
  SessionDiscount? _appliedDiscount;
  String? _couponError;
  bool _couponBusy = false;

  /// Physical copies of each selected image (1–[AppConstants.kMaxPrintCopies]).
  int _printCopies = AppConstants.kDefaultPrintCopies;

  final bool _isProcessing = false;
  String? _errorMessage;
  String _printerHost;

  // Print/Share state
  bool _isSilentPrinting = false;
  bool _isDialogPrinting = false;
  bool _isPrintingReceipt = false;
  bool _postPaymentPrintStarted = false;
  bool _postPaymentReceiptPrintStarted = false;
  PrintProgressSnapshot _printProgress = const PrintProgressSnapshot();
  Timer? _printProgressTicker;
  DateTime? _printFinishingStartedAt;
  int _printFinishingPageIndex = 0;
  int _printFinishingTotalPages = 0;
  bool _isSharing = false;
  bool _isDownloading = false;
  String _downloadMessage = '';
  Future<void>? _silentPrintInflight;
  Future<bool>? _downloadInflight;

  // Track which action initiated the download
  String _downloadingForAction = ''; // 'silent', 'dialog', 'share'

  // Downloaded files for each image
  final Map<String, XFile> _downloadedFiles = {};

  String? _paymentLink;
  String? _qrImageUrl;
  String? _upiLink;
  String? _paymentInitError;
  bool _paymentInitInProgress = false;
  int _paymentInitiateAttempts = 0;
  int _paymentInitiateGeneration = 0;

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

  /// Set when an FCM payment push is handled on the Pay & Collect screen (inline UI, no dialog).
  String? _fcmPaymentStatusDetail;
  bool? _fcmPaymentPushSuccess;

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
  bool get hasPaymentQrPayload => paymentQrPayloadPresent(
        qrImageUrl: _qrImageUrl,
        upiLink: _upiLink,
        paymentLink: _paymentLink,
      );

  /// Stops payment/session polling (e.g. before customer deletes photos).
  void stopPaymentPolling() {
    _paymentIdPollTimer?.cancel();
    _paymentIdPollTimer = null;
    _sessionPollTimer?.cancel();
    _sessionPollTimer = null;
  }

  /// Re-runs payment initiate (e.g. when the first response had an id but no QR).
  Future<void> retryLoadPaymentQr({String? customerPhone}) {
    _paymentInitiateAttempts = 0;
    _paymentInitiateGeneration += 1;
    _activePaymentId = null;
    _paymentInitError = null;
    return loadPaymentQr(customerPhone: customerPhone, force: true);
  }

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

  String? get customerName =>
      _contact.customerName.isEmpty ? null : _contact.customerName;
  String? get customerPhone =>
      _contact.customerPhone.isEmpty ? null : _contact.customerPhone;
  bool get customerWhatsappOptIn => _contact.whatsappOptIn;
  String? get customerEmail =>
      _contact.customerEmail.isEmpty ? null : _contact.customerEmail;
  bool get marketingEmailOptIn => _contact.marketingEmailOptIn;
  bool get marketingSmsOptIn => _contact.marketingSmsOptIn;
  bool get marketingWhatsappOptIn => _contact.marketingWhatsappOptIn;

  SessionDiscount? get appliedDiscount => _appliedDiscount;
  String? get couponError => _couponError;
  bool get couponBusy => _couponBusy;

  /// WhatsApp queue is only meaningful when a phone exists and the user opted in.
  bool get effectiveWhatsappOptIn {
    final p = _contact.customerPhone.trim();
    return p.isNotEmpty && _contact.whatsappOptIn;
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
    ReceiptPrinterService? receiptPrinterService,
    CustomerContactCapture? contact,
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
        _receiptPrinterService =
            receiptPrinterService ?? ReceiptPrinterService(),
        _contact = contact ??
            CustomerContactCapture(
              customerName: customerName ?? '',
              customerPhone: customerPhone ?? '',
              whatsappOptIn: customerWhatsappOptIn,
            ),
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
    return resolvePrinterEndpoint(manager?.settings).host;
  }

  PrinterEndpoint get _printerEndpoint =>
      resolvePrinterEndpoint(_appSettingsManager?.settings);

  /// Sync host/port/path from latest `/api/settings` (e.g. after fetch on Pay screen).
  void refreshPrinterFromSettings({bool notify = true}) {
    final endpoint = _printerEndpoint;
    final nextHost = endpoint.host;
    if (nextHost == _printerHost) return;
    _printerHost = nextHost;
    if (notify) notifyListeners();
  }

  /// Port from `/api/settings` when valid; otherwise HTTP default (80).
  int get effectivePrinterPort => _printerEndpoint.port;

  String get effectivePrinterPath => _printerEndpoint.path;

  int get initialPrintPrice =>
      _appSettingsManager?.settings?.initialPrice ??
      AppConstants.kDefaultInitialPrintPrice;

  int get additionalPrintPrice =>
      _appSettingsManager?.settings?.additionalPrintPrice ??
      AppConstants.kDefaultAdditionalPrintPrice;

  bool get isSilentPrinting => _isSilentPrinting;
  bool get isDialogPrinting => _isDialogPrinting;
  bool get isPrintingReceipt => _isPrintingReceipt;
  bool get isPrinting =>
      _isSilentPrinting || _isDialogPrinting || _isPrintingReceipt;
  PrintProgressSnapshot get printProgress => _printProgress;

  /// True when admin enabled a LAN thermal receipt printer.
  bool get isReceiptPrinterConfigured {
    final settings = _appSettingsManager?.settings;
    if (settings?.receiptPrinterEnabled != true) return false;
    final host = settings?.receiptPrinterHost?.trim() ?? '';
    return host.isNotEmpty;
  }

  /// True when the QR share screen should show the print status card.
  bool get shouldShowPrintProgressCard {
    if (kIsWeb) return false;
    return _appSettingsManager?.settings?.printerEnabled ?? true;
  }
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

  /// Get total price based on number of photos × copies (full cart value).
  int get totalPrice {
    if (_generatedImages.isEmpty) return 0;
    final sheets = printSheetCount;
    final basePrice = initialPrintPrice;
    final additionalPrice = additionalPrintPrice;
    return basePrice +
        (sheets > 1 ? (sheets - 1) * additionalPrice : 0);
  }

  bool get collectPaymentBeforeGeneration =>
      payment_workflow.collectPaymentBeforeGeneration(
        _appSettingsManager?.settings?.paymentCollectionTiming,
      );

  /// Copies of each selected photo to print (default 1).
  int get printCopies => _printCopies;

  /// Total physical sheets = selected images × [printCopies].
  int get printSheetCount => payment_workflow.resolvePrintSheetCount(
        imageCount: _generatedImages.length,
        copiesPerImage: _printCopies,
      );

  /// True while the guest can still change copy count (before payment settles).
  bool get canChangePrintCopies =>
      !_paymentOutcomeHandled && _fcmPaymentPushSuccess != true;

  /// Cart subtotal before coupon (may be less when pre-paid).
  int get checkoutAmount => payment_workflow.resolveCheckoutAmount(
        collectPaymentBeforeGeneration: collectPaymentBeforeGeneration,
        imageCount: _generatedImages.length,
        initialPrintPrice: initialPrintPrice,
        additionalPrintPrice: additionalPrintPrice,
        copiesPerImage: _printCopies,
      );

  /// Amount charged on initiate — uses applied coupon [SessionDiscount.finalAmount].
  int get chargeAmount {
    final d = _appliedDiscount;
    if (d == null) return checkoutAmount;
    return d.chargeAmount;
  }

  /// Updates the printer host (hostname or IP) shown in the print options field.
  void setPrinterHost(String host) {
    _printerHost = host.trim();
    notifyListeners();
  }

  /// Sets physical copies per selected image and refreshes UPI QR for the new total.
  Future<void> setPrintCopies(int copies) async {
    if (!canChangePrintCopies) return;
    final next = copies.clamp(
      AppConstants.kDefaultPrintCopies,
      AppConstants.kMaxPrintCopies,
    );
    if (next == _printCopies) return;
    _printCopies = next;
    if (_appliedDiscount != null) {
      _appliedDiscount = null;
      _couponError = null;
    }
    notifyListeners();
    if (checkoutAmount <= 0) {
      _paymentLink = null;
      _qrImageUrl = null;
      _upiLink = null;
      _activePaymentId = null;
      stopPaymentPolling();
      notifyListeners();
      return;
    }
    await loadPaymentQr(force: true);
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
    _printProgressTicker?.cancel();
    super.dispose();
  }
}
