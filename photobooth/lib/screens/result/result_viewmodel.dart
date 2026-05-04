import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../photo_generate/photo_generate_viewmodel.dart';
import '../photo_capture/photo_model.dart';
import '../../services/api_service.dart';
import '../../services/app_settings_manager.dart';
import '../../services/file_helper.dart';
import '../../services/print_service.dart';
import '../../services/session_manager.dart';
import '../../services/share_service.dart';
import '../../services/kiosk_manager.dart';
import '../../utils/constants.dart';
import '../../utils/exceptions.dart';
import '../../utils/logger.dart';
import '../../services/error_reporting/error_reporting_manager.dart';
import '../../services/fcm_service.dart';
import '../../services/payment_push_coordinator.dart';
import '../../services/whatsapp_push_coordinator.dart';
import '../../models/kiosk_share_link_model.dart';

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

class ResultViewModel extends ChangeNotifier {
  final List<GeneratedImage> _generatedImages;
  final PhotoModel? _originalPhoto;
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

  /// Loads UPI payment link from POST /api/payment/initiate and exposes it for QR display.
  Future<void> loadPaymentQr({String? customerPhone}) async {
    if (_paymentInitInProgress || _paymentLink != null) return;
    final sessionId = _sessionManager.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      _paymentInitError = 'No session for payment. Go back and try again.';
      notifyListeners();
      return;
    }

    _paymentInitInProgress = true;
    _paymentInitError = null;
    _activePaymentId = null;
    _paymentIdPollTimer?.cancel();
    _sessionPollTimer?.cancel();
    _paymentIdPollTicks = 0;
    _sessionPollTicks = 0;
    _paymentIdNullStreak = 0;
    _sessionNullStreak = 0;
    _paymentIdConsecutiveFailureTicks = 0;
    _sessionConsecutiveFailureTicks = 0;
    _paymentOutcomeHandled = false;
    notifyListeners();

    try {
      final fcmToken = await FcmService.getToken();
      if (kDebugMode) {
        final len = fcmToken?.length ?? 0;
        AppLogger.debug(
          'Payment initiate: fcmToken length=$len'
          '${len == 0 ? " — server cannot send FCM; check permission / Play services" : ""}',
        );
      }
      final result = await _apiService.initiatePayment(
        sessionId: sessionId,
        amount: totalPrice,
        customerPhone: customerPhone,
        fcmToken: fcmToken ?? '',
      );
      if (kDebugMode) {
        AppLogger.debug(
          'Payment initiate OK: id=${result.id} status=${result.status} — '
          'confirm backend stores token + sends FCM from same Firebase project as the app',
        );
      }
      // For manual/static QR mode, backend may omit paymentLink but should still
      // create a transaction with an id that admin can approve/reject.
      _paymentLink = result.paymentLink;
      final pid = result.id.trim();
      _activePaymentId = pid.isNotEmpty ? pid : null;
      if (_activePaymentId != null) {
        _startPaymentStatusPolling();
      }
      // Backup: also poll session by sessionId (React Query style) so approval can
      // still be detected even if paymentId polling/FCM is missing.
      _startSessionApprovalPolling(sessionId);
    } on ApiException catch (e) {
      _paymentInitError = e.message;
    } catch (e) {
      _paymentInitError = 'Payment setup failed: $e';
    } finally {
      _paymentInitInProgress = false;
      notifyListeners();
    }
  }

  /// Kiosk polling backup cadence: every 3 seconds.
  static const _paymentPollInterval = Duration(seconds: 3);

  void _startPaymentStatusPolling() {
    _paymentIdPollTimer?.cancel();
    _paymentIdPollTicks = 0;
    _paymentIdNullStreak = 0;
    _paymentIdConsecutiveFailureTicks = 0;
    _paymentIdPollTimer = Timer.periodic(
      _paymentPollInterval,
      _onPaymentPollTick,
    );
  }

  void _startSessionApprovalPolling(String sessionId) {
    _sessionPollTimer?.cancel();
    _sessionPollTicks = 0;
    _sessionNullStreak = 0;
    _sessionConsecutiveFailureTicks = 0;
    _sessionPollTimer = Timer.periodic(
      _paymentPollInterval,
      (t) => _onSessionPollTick(t, sessionId),
    );
  }

  Future<void> _onSessionPollTick(Timer t, String sessionId) async {
    if (_paymentOutcomeHandled) {
      t.cancel();
      return;
    }
    if (++_sessionPollTicks > 180) {
      // 12 minutes max.
      t.cancel();
      return;
    }

    Map<String, dynamic>? raw;
    try {
      raw = await _apiService.fetchSession(sessionId);
    } catch (_) {
      raw = null;
    }
    if (_disposed) {
      t.cancel();
      return;
    }
    if (_paymentOutcomeHandled) {
      t.cancel();
      return;
    }
    if (raw == null) {
      if (++_sessionNullStreak >= 8) {
        // Keep polling, but allow UI to surface a "stuck" fallback.
      }
      _sessionConsecutiveFailureTicks += 1;
      if (_sessionConsecutiveFailureTicks == 10) notifyListeners();
      return;
    }
    _sessionNullStreak = 0;
    _sessionConsecutiveFailureTicks = 0;

    final verdict = _verdictFromSession(raw);
    switch (verdict) {
      case _PollVerdict.approved:
        t.cancel();
        await onFcmPaymentPush(
          PaymentPushPayload(
            type: PaymentPushCoordinator.typeApproved,
            paymentId: sessionId,
            title: 'Payment confirmed',
            body: 'Payment approved. Printing...',
          ),
        );
      case _PollVerdict.failed:
        t.cancel();
        await onFcmPaymentPush(
          PaymentPushPayload(
            type: PaymentPushCoordinator.typeFailed,
            paymentId: sessionId,
            title: 'Payment not completed',
            body: 'Payment failed. Try again or use another method.',
          ),
        );
      case _PollVerdict.pending:
      case null:
        break;
    }
  }

  static _PollVerdict? _verdictFromSession(Map<String, dynamic> raw) {
    dynamic pick(List<String> keys) {
      for (final k in keys) {
        if (raw.containsKey(k)) return raw[k];
      }
      return null;
    }

    final paidFlag = pick(const [
      'paymentApproved',
      'payment_approved',
      'isPaid',
      'paid',
      'paymentConfirmed',
    ]);
    if (paidFlag is bool) {
      return paidFlag ? _PollVerdict.approved : _PollVerdict.pending;
    }

    final status = pick(const [
      'paymentStatus',
      'payment_status',
      'status',
    ])?.toString().trim().toUpperCase();
    if (status == null || status.isEmpty) return null;
    if (status == 'APPROVED' || status == 'PAID' || status == 'CONFIRMED') {
      return _PollVerdict.approved;
    }
    if (status == 'FAILED' || status == 'DECLINED' || status == 'REJECTED') {
      return _PollVerdict.failed;
    }
    return _PollVerdict.pending;
  }

  Future<void> _onPaymentPollTick(Timer t) async {
    if (_paymentOutcomeHandled) {
      t.cancel();
      return;
    }
    if (++_paymentIdPollTicks > 90) {
      t.cancel();
      return;
    }
    final id = _activePaymentId;
    if (id == null || id.isEmpty) {
      t.cancel();
      return;
    }

    Map<String, dynamic>? raw;
    try {
      raw = await _apiService.fetchPaymentStatus(id);
    } catch (_) {
      raw = null;
    }
    if (_disposed) {
      t.cancel();
      return;
    }
    if (_paymentOutcomeHandled) {
      t.cancel();
      return;
    }
    if (raw == null) {
      if (++_paymentIdNullStreak >= 8) {
        // Keep polling, but allow UI to surface a "stuck" fallback.
      }
      _paymentIdConsecutiveFailureTicks += 1;
      if (_paymentIdConsecutiveFailureTicks == 10) notifyListeners();
      return;
    }
    _paymentIdNullStreak = 0;
    _paymentIdConsecutiveFailureTicks = 0;

    final verdict = _verdictFromPaymentStatusResponse(raw);
    switch (verdict) {
      case _PollVerdict.approved:
        t.cancel();
        await onFcmPaymentPush(
          PaymentPushPayload(
            type: PaymentPushCoordinator.typeApproved,
            paymentId: id,
            title: 'Payment confirmed',
            body: 'Payment approved. Proceed to print your photo.',
          ),
        );
      case _PollVerdict.failed:
        t.cancel();
        await onFcmPaymentPush(
          PaymentPushPayload(
            type: PaymentPushCoordinator.typeFailed,
            paymentId: id,
            title: 'Payment not completed',
            body: 'Payment failed. Try again or use another method.',
          ),
        );
      case _PollVerdict.pending:
      case null:
        break;
    }
  }

  /// Parses `GET /api/payments/status/{id}` body: `status` is PENDING | APPROVED | FAILED.
  static _PollVerdict? _verdictFromPaymentStatusResponse(
    Map<String, dynamic> raw,
  ) {
    final s = raw['status']?.toString().trim().toUpperCase();
    if (s == null || s.isEmpty) return null;
    switch (s) {
      case 'APPROVED':
        return _PollVerdict.approved;
      case 'FAILED':
        return _PollVerdict.failed;
      case 'PENDING':
        return _PollVerdict.pending;
      default:
        return _PollVerdict.pending;
    }
  }

  /// First caller (FCM or status poll) wins; the other sees [false] and does nothing — no double print.
  bool _tryClaimPaymentOutcome() {
    if (_paymentOutcomeHandled) return false;
    _paymentOutcomeHandled = true;
    _paymentIdPollTimer?.cancel();
    _paymentIdPollTimer = null;
    _sessionPollTimer?.cancel();
    _sessionPollTimer = null;
    return true;
  }

  /// CTA: force a client-side refresh of polling state.
  ///
  /// Does not re-initiate payment (no new payment id); it just resets failure
  /// streaks and restarts the timers so operators can recover from transient
  /// connectivity / backend hiccups.
  Future<void> refreshPaymentPolling() async {
    if (_paymentOutcomeHandled) return;
    final sessionId = _sessionManager.sessionId;
    if (sessionId == null || sessionId.trim().isEmpty) return;

    _paymentIdConsecutiveFailureTicks = 0;
    _sessionConsecutiveFailureTicks = 0;
    _paymentIdNullStreak = 0;
    _sessionNullStreak = 0;
    notifyListeners();

    // Fire a one-shot refresh first (gives instant feedback), then restart cadence.
    try {
      final raw = await _apiService.fetchSession(sessionId);
      if (_disposed) return;
      if (raw != null) {
        final verdict = _verdictFromSession(raw);
        if (verdict == _PollVerdict.approved) {
          await onFcmPaymentPush(
            PaymentPushPayload(
              type: PaymentPushCoordinator.typeApproved,
              paymentId: sessionId,
              title: 'Payment confirmed',
              body: 'Payment approved. Printing...',
            ),
          );
          return;
        }
        if (verdict == _PollVerdict.failed) {
          await onFcmPaymentPush(
            PaymentPushPayload(
              type: PaymentPushCoordinator.typeFailed,
              paymentId: sessionId,
              title: 'Payment not completed',
              body: 'Payment failed. Try again or use another method.',
            ),
          );
          return;
        }
      }
    } catch (_) {
      // ignore (fallback is just a restart)
    }
    if (_disposed) return;

    _startSessionApprovalPolling(sessionId);
    if (_activePaymentId != null && _activePaymentId!.trim().isNotEmpty) {
      _startPaymentStatusPolling();
    }
  }

  /// FCM or poll: updates inline Pay & Collect; on approval runs [silentPrintToNetwork] once.
  ///
  /// Also kicks off [ensurePostPaymentShareArtifacts] in parallel with print, so the
  /// receipt POST + WhatsApp queue happens the moment payment is approved — even if
  /// the user/operator never reaches the QR/Thank You navigation step.
  Future<void> onFcmPaymentPush(PaymentPushPayload payload) async {
    if (!payload.isApproved && !payload.isFailed) return;
    if (!_tryClaimPaymentOutcome()) return;

    if (payload.isApproved) {
      _fcmPaymentPushSuccess = true;
      _fcmPaymentStatusDetail = _fcmApprovedDetailText(payload);
      notifyListeners();

      // Fire-and-forget: queue receipt + WhatsApp send in parallel with print.
      // ensurePostPaymentShareArtifacts is internally idempotent
      // (_postPaymentSharePrepared) so calling it again from
      // _navigateToThankYouIfEligible is a no-op.
      unawaited(ensurePostPaymentShareArtifacts());

      try {
        await silentPrintToNetwork().timeout(const Duration(minutes: 2));
      } on TimeoutException {
        _errorMessage =
            'Printing is taking longer than expected. Please check the printer connection and try again.';
      }
      notifyListeners();
      return;
    }
    _fcmPaymentPushSuccess = false;
    _fcmPaymentStatusDetail = _fcmFailedDetailText(payload);
    notifyListeners();
  }

  static String _fcmApprovedDetailText(PaymentPushPayload payload) {
    final body = payload.body ??
        (payload.amount != null && payload.amount!.isNotEmpty
            ? '₹${payload.amount} paid successfully. Proceed to print your photo.'
            : 'Payment approved. Proceed to print your photo.');
    final title = payload.title?.trim();
    if (title != null && title.isNotEmpty) {
      return '$title\n$body';
    }
    return body;
  }

  static String _fcmFailedDetailText(PaymentPushPayload payload) {
    final body = payload.body ??
        'Your payment could not be confirmed. Try again or use another method.';
    final title = payload.title?.trim();
    if (title != null && title.isNotEmpty) {
      return '$title\n$body';
    }
    return body;
  }

  /// Deletes the session on the server (DELETE /api/sessions/{sessionId}) and clears local session.
  /// Call after user confirms "Delete my photos". Throws [ApiException] on API failure.
  Future<void> deleteSession() async {
    final sessionId = _sessionManager.sessionId;
    if (sessionId == null) return;
    await _apiService.deleteSession(sessionId);
    _sessionManager.clearSession();
  }

  /// Kiosk privacy wipe: clears local session + temp image files so the next user cannot access prior photos.
  ///
  /// This does **not** delete anything on the server (transactions/audit can remain).
  Future<void> privacyWipeLocal() async {
    _paymentIdPollTimer?.cancel();
    _paymentIdPollTimer = null;
    _sessionPollTimer?.cancel();
    _sessionPollTimer = null;
    stopWhatsappDeliveryPolling();
    _downloadedFiles.clear();
    _sessionManager.clearSession();
    await FileHelper.cleanupTempImages();
  }

  static String? _firstNonEmptyString(dynamic v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  static Map<String, dynamic>? _asStringKeyedMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  static String? _pickWhatsappDeliveryStatus(Map<String, dynamic> raw) {
    const keys = [
      'whatsappDeliveryStatus',
      'whatsapp_delivery_status',
      'waDeliveryStatus',
      'wa_delivery_status',
    ];
    for (final k in keys) {
      final s = _firstNonEmptyString(raw[k]);
      if (s != null) return s;
    }
    final session = _asStringKeyedMap(raw['session']);
    if (session == null) return null;
    for (final k in keys) {
      final s = _firstNonEmptyString(session[k]);
      if (s != null) return s;
    }
    return null;
  }

  void _applyWhatsappDeliveryStatus(String? status, {String? detail}) {
    final next = status?.trim();
    if (next == null || next.isEmpty) return;
    if (_whatsappDeliveryStatus == next &&
        (detail == null || detail == _whatsappDeliveryDetail)) {
      return;
    }
    _whatsappDeliveryStatus = next;
    if (detail != null) {
      _whatsappDeliveryDetail = detail;
    }
    notifyListeners();
  }

  void applyWhatsappStatusPush(WhatsAppStatusPayload payload) {
    final sid = _sessionManager.sessionId?.trim() ?? '';
    if (sid.isEmpty || sid != payload.sessionId.trim()) return;
    _applyWhatsappDeliveryStatus(
      payload.status,
      detail: payload.error,
    );
    final upper = payload.status.trim().toUpperCase();
    if (_isTerminalWhatsappStatus(upper)) {
      stopWhatsappDeliveryPolling();
    }
  }

  /// Backend's canonical WhatsApp delivery status set is a Postgres enum with
  /// exactly 6 values, normalized from MSG91's raw vocabulary by the server's
  /// `mapMsg91Status()` before any DB write:
  ///
  ///   PENDING   — receipt endpoint queued the dispatch (initial)
  ///   SENT      — MSG91 ACK'd; awaiting delivery webhook (intermediate)
  ///   DELIVERED — MSG91 reported delivered (terminal for our polling)
  ///   READ      — MSG91 reported read; backfills whatsappDeliveredAt
  ///   FAILED    — dispatch rejected / webhook reported failure (ignored
  ///               server-side once status reached DELIVERED or READ)
  ///   SKIPPED   — opted out / no phone (terminal, set once)
  ///
  /// State machine is monotonic forward (PENDING → SENT → DELIVERED → READ),
  /// so we treat anything past SENT as terminal for *polling* purposes — even
  /// though READ can still arrive later, it'll come via FCM push.
  bool _isTerminalWhatsappStatus(String upper) {
    switch (upper) {
      case 'DELIVERED':
      case 'READ':
      case 'FAILED':
      case 'SKIPPED':
        return true;
      default:
        return false;
    }
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

  Future<bool> refreshWhatsappDeliveryStatusFromSession() async {
    final sid = _sessionManager.sessionId;
    if (sid == null || sid.trim().isEmpty) return false;
    Map<String, dynamic>? raw;
    try {
      raw = await _apiService.fetchSession(sid);
    } catch (_) {
      raw = null;
    }
    if (_disposed) return false;
    if (raw == null) return false;
    final st = _pickWhatsappDeliveryStatus(raw);
    _applyWhatsappDeliveryStatus(st);
    final upper = st?.trim().toUpperCase() ?? '';
    if (_isTerminalWhatsappStatus(upper)) {
      stopWhatsappDeliveryPolling();
    }
    return true;
  }

  void startWhatsappDeliveryPolling() {
    if (kIsWeb) return;
    if (!effectiveWhatsappOptIn) return;
    stopWhatsappDeliveryPolling();
    _whatsappPollTicks = 0;

    var consecutiveFailures = 0;
    Duration nextDelay = const Duration(seconds: 3);

    void scheduleNext() {
      _whatsappPollTimer?.cancel();
      _whatsappPollTimer = Timer(nextDelay, () async {
        if (++_whatsappPollTicks > 120) {
          stopWhatsappDeliveryPolling();
          return;
        }

        final ok = await refreshWhatsappDeliveryStatusFromSession();
        if (_whatsappPollTimer == null) return; // stopped due to terminal status

        if (ok) {
          consecutiveFailures = 0;
          nextDelay = const Duration(seconds: 3);
        } else {
          consecutiveFailures += 1;
          final factor = 1 << (consecutiveFailures.clamp(0, 4));
          final seconds = (3 * factor).clamp(3, 30);
          nextDelay = Duration(seconds: seconds);
        }

        scheduleNext();
      });
    }

    scheduleNext();
  }

  void stopWhatsappDeliveryPolling() {
    _whatsappPollTimer?.cancel();
    _whatsappPollTimer = null;
    _whatsappPollTicks = 0;
  }

  void _ingestReceiptShareFields(Map<String, dynamic> raw) {
    final share = _asStringKeyedMap(raw['share']) ??
        _asStringKeyedMap(raw['digitalCopy']) ??
        _asStringKeyedMap(raw['digital_copy']);

    final String? url = _firstNonEmptyString(raw['shareUrl']) ??
        _firstNonEmptyString(raw['url']) ??
        _firstNonEmptyString(share?['url']) ??
        _firstNonEmptyString(share?['shortUrl']) ??
        _firstNonEmptyString(share?['short_url']);

    final String? longUrl = _firstNonEmptyString(raw['shareLongUrl']) ??
        _firstNonEmptyString(raw['longUrl']) ??
        _firstNonEmptyString(share?['longUrl']) ??
        _firstNonEmptyString(share?['long_url']);

    final DateTime? exp = _parseDate(raw['shareExpiresAt']) ??
        _parseDate(raw['expiresAt']) ??
        _parseDate(share?['expiresAt']) ??
        _parseDate(share?['expires_at']);

    final pdf = _firstNonEmptyString(raw['receiptPdfUrl']) ??
        _firstNonEmptyString(raw['pdfUrl']) ??
        _firstNonEmptyString(raw['receiptPdf']) ??
        _firstNonEmptyString(_asStringKeyedMap(raw['receipt'])?['pdfUrl']);

    if (url != null) _receiptShareUrl = url;
    if (longUrl != null) _receiptShareLongUrl = longUrl;
    if (exp != null) _receiptShareExpiresAt = exp;
    if (pdf != null) _receiptPdfUrl = pdf;

    // Trust the server's explicit `whatsappQueued` boolean (true OR false).
    // Backend now returns this on every receipt response. Only fall back to
    // the older `whatsappRequested` field if `whatsappQueued` isn't present.
    final waQueuedRaw = raw['whatsappQueued'] ?? raw['whatsapp_queued'];
    if (waQueuedRaw is bool) {
      _whatsappQueued = waQueuedRaw;
    } else {
      final legacy = raw['whatsappRequested'] == true ||
          raw['whatsapp_requested'] == true;
      if (legacy) _whatsappQueued = true;
    }

    final skipReason = _firstNonEmptyString(raw['whatsappSkipReason']) ??
        _firstNonEmptyString(raw['whatsapp_skip_reason']);
    if (skipReason != null) {
      _whatsappSkipReason = skipReason.toLowerCase();
    }

    final pdfErr = _firstNonEmptyString(raw['pdfError']) ??
        _firstNonEmptyString(raw['pdf_error']);
    if (pdfErr != null) {
      _pdfError = pdfErr;
    }

    final st = _pickWhatsappDeliveryStatus(raw);
    if (st != null) {
      _whatsappDeliveryStatus = st;
    }
  }

  /// After payment approval: request canonical receipt/share link + mint kiosk fallback.
  ///
  /// Concurrent-safe: callers from both [onFcmPaymentPush] and the navigation path
  /// share a single in-flight Future, so the receipt POST never fires twice.
  Future<void> ensurePostPaymentShareArtifacts() {
    if (_postPaymentSharePrepared) return Future<void>.value();
    final inflight = _postPaymentInflight;
    if (inflight != null) return inflight;
    final fut = _runPostPaymentShareArtifacts();
    _postPaymentInflight = fut;
    return fut.whenComplete(() {
      _postPaymentInflight = null;
    });
  }

  Future<void> _runPostPaymentShareArtifacts() async {
    final sessionId = _sessionManager.sessionId;
    if (sessionId == null || sessionId.trim().isEmpty) {
      _postPaymentSharePrepared = true;
      return;
    }

    KioskShareLinkModel? kiosk;
    try {
      kiosk = await mintCustomerShareLink();
      if (_disposed) return;
      if (kiosk != null && kiosk.isValid) {
        _kioskFallbackShareUrl = kiosk.url;
        _kioskFallbackShareLongUrl = kiosk.longUrl;
        _kioskFallbackShareExpiresAt = kiosk.expiresAt;
      }
    } catch (e, st) {
      AppLogger.debug('post-payment kiosk share mint failed: $e\n$st');
    }
    if (_disposed) return;

    try {
      final fcmToken = kIsWeb ? null : await FcmService.getToken();
      if (_disposed) return;
      final receipt = await _postSessionReceiptWithRetry(
        sessionId: sessionId,
        fcmToken: fcmToken,
      );
      if (_disposed) return;
      if (receipt != null) {
        _receiptResponseReceived = true;
        _ingestReceiptShareFields(receipt);
        // NOTE: do NOT override _whatsappQueued from the client-side opt-in
        // here — the server is now authoritative on whether WhatsApp was
        // actually queued (it can refuse for invalid_phone / no_phone even
        // when the user opted in). _ingestReceiptShareFields already sets
        // _whatsappQueued from the response.
      }
    } catch (e, st) {
      // _postSessionReceiptWithRetry already reports + logs; this is a safety net.
      AppLogger.debug('postSessionReceipt failed (outer): $e\n$st');
    }
    if (_disposed) return;

    // If receipt didn't include a share URL, fall back to kiosk mint (if any).
    final ru = _receiptShareUrl?.trim() ?? '';
    if (ru.isEmpty) {
      final ku = _kioskFallbackShareUrl?.trim() ?? '';
      if (ku.isNotEmpty) {
        _receiptShareUrl = _kioskFallbackShareUrl;
        if ((_receiptShareLongUrl?.trim() ?? '').isEmpty) {
          _receiptShareLongUrl = _kioskFallbackShareLongUrl;
        }
        _receiptShareExpiresAt ??= _kioskFallbackShareExpiresAt;
      }
    }

    _postPaymentSharePrepared = true;
    await refreshWhatsappDeliveryStatusFromSession();
    notifyListeners();
  }

  /// Posts the receipt with retry + error reporting.
  ///
  /// - Retries on transient failures (network, timeout, 5xx, no statusCode).
  /// - Does **not** retry on 4xx (bad input / server rule violation — won't recover).
  /// - On terminal failure, reports to [ErrorReportingManager] (Bugsnag) with context
  ///   so we can alert/debug, instead of silently dropping the WhatsApp send.
  Future<Map<String, dynamic>?> _postSessionReceiptWithRetry({
    required String sessionId,
    String? fcmToken,
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    StackTrace? lastStack;
    int? lastStatus;

    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await _apiService.postSessionReceipt(
          sessionId: sessionId,
          customerName: _customerName,
          customerPhone: _customerPhone,
          whatsappOptIn: effectiveWhatsappOptIn,
          transactionRef: _activePaymentId,
          fcmToken: fcmToken,
        );
      } on ApiException catch (e, st) {
        lastError = e;
        lastStack = st;
        lastStatus = e.statusCode;

        final transient = e.statusCode == null ||
            (e.statusCode != null && e.statusCode! >= 500);
        if (!transient || attempt == maxAttempts) {
          break;
        }
        // Exponential backoff: 500ms, 1s, 2s
        final delayMs = 500 * (1 << (attempt - 1));
        AppLogger.debug(
          'postSessionReceipt transient failure (status=${e.statusCode}, '
          'attempt=$attempt/$maxAttempts), retrying in ${delayMs}ms: ${e.message}',
        );
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        // Unknown errors: treat as transient up to maxAttempts.
        if (attempt == maxAttempts) break;
        final delayMs = 500 * (1 << (attempt - 1));
        AppLogger.debug(
          'postSessionReceipt unknown failure (attempt=$attempt/$maxAttempts), '
          'retrying in ${delayMs}ms: $e',
        );
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }

    // All attempts exhausted (or hit a non-retryable 4xx). Report and surface.
    AppLogger.debug('postSessionReceipt giving up: $lastError');
    await ErrorReportingManager.recordError(
      lastError ?? Exception('postSessionReceipt unknown failure'),
      lastStack,
      reason: 'postSessionReceipt failed after retries',
      extraInfo: {
        'sessionId': sessionId,
        'transactionRef': _activePaymentId,
        'whatsappOptIn': effectiveWhatsappOptIn,
        'hasCustomerPhone': (_customerPhone?.trim().isNotEmpty ?? false),
        'hasFcmToken': (fcmToken?.isNotEmpty ?? false),
        'lastStatusCode': lastStatus,
        'maxAttempts': maxAttempts,
      },
    );
    return null;
  }

  /// Mints a short-lived customer share link for this session (for QR bridge).
  ///
  /// Returns null if kiosk/session context is missing or the backend rejects it.
  Future<KioskShareLinkModel?> mintCustomerShareLink({
    int? ttlMinutes,
    int? imageIndex,
  }) async {
    final sessionId = _sessionManager.sessionId;
    if (sessionId == null || sessionId.trim().isEmpty) return null;
    final kioskCode = await _kioskManager.getKioskCode();
    if (kioskCode == null || kioskCode.trim().isEmpty) return null;

    try {
      final raw = await _apiService.createKioskShareLink(
        kioskCode: kioskCode,
        sessionId: sessionId,
        ttlMinutes: ttlMinutes,
        imageIndex: imageIndex,
      );
      final model = KioskShareLinkModel.fromJson(raw);
      return model.isValid ? model : null;
    } catch (e, st) {
      AppLogger.debug('mintCustomerShareLink failed: $e\n$st');
      return null;
    }
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
    // Web share: share the URLs (no filesystem downloads / file sharing).
    if (kIsWeb) {
      final urls = _generatedImages.map((e) => e.imageUrl).where((u) => u.trim().isNotEmpty).toList();
      if (urls.isEmpty) {
        _errorMessage = 'No images to share';
        notifyListeners();
        return;
      }
      _isSharing = true;
      _errorMessage = null;
      notifyListeners();
      try {
        await _shareService.shareText(
          urls.join('\n'),
          sharePositionOrigin: sharePositionOrigin,
          subject: '${AppConstants.kBrandName} photos',
        );
      } on ShareException catch (e) {
        // Many browsers don't support Web Share API for desktops.
        // Fall back to copying the link(s) so operators can paste into WhatsApp.
        try {
          await Clipboard.setData(ClipboardData(text: urls.join('\n')));
          _errorMessage = 'Sharing not supported in this browser. Link copied.';
        } catch (_) {
          _errorMessage = e.message;
        }
      } catch (e) {
        _errorMessage = 'Failed to share: $e';
      } finally {
        _isSharing = false;
        notifyListeners();
      }
      return;
    }

    // Download files first if needed
    if (_downloadedFilesList.length != _generatedImages.length) {
      final success = await _ensureAllFilesDownloaded('share');
      if (!success) return;
    }

    _isSharing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final files = _downloadedFilesList;
      if (files.isEmpty) {
        throw ShareException('No images to share (download did not produce any files)');
      }
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
