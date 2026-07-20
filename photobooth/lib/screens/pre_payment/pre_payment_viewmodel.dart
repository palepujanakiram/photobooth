import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/payment_initiate_result.dart';
import '../../models/session_discount.dart';
import '../../services/api_service.dart';
import '../../services/app_settings_manager.dart';
import '../../services/fcm_service.dart';
import '../../services/payment_push_coordinator.dart';
import '../../services/session_manager.dart';
import '../../utils/app_strings.dart';
import '../../utils/constants.dart';
import '../../utils/error_reporting_helpers.dart';
import '../../utils/exceptions.dart';
import '../../utils/session_photo_sync_helpers.dart';
import '../photo_capture/photo_model.dart';
import '../result/result_payment_poll_helpers.dart';

/// Collects initial UPI payment before AI generation when configured.
class PrePaymentViewModel extends ChangeNotifier {
  PrePaymentViewModel({
    required AppSettingsManager appSettingsManager,
    ApiService? apiService,
    SessionManager? sessionManager,
  })  : _appSettingsManager = appSettingsManager,
        _apiService = apiService ?? ApiService(),
        _sessionManager = sessionManager ?? SessionManager();

  final AppSettingsManager _appSettingsManager;
  final ApiService _apiService;
  final SessionManager _sessionManager;

  String? _paymentLink;
  String? _qrImageUrl;
  String? _upiLink;
  String? _paymentInitError;
  bool _paymentInitInProgress = false;
  int _paymentInitiateAttempts = 0;
  int _paymentInitiateGeneration = 0;
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
  String? _fcmPaymentStatusDetail;
  bool? _fcmPaymentPushSuccess;
  bool _disposed = false;
  SessionDiscount? _appliedDiscount;
  String? _couponError;
  bool _couponBusy = false;

  VoidCallback? onApproved;

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
  String? get fcmPaymentStatusDetail => _fcmPaymentStatusDetail;
  bool? get fcmPaymentPushSuccess => _fcmPaymentPushSuccess;
  bool get isPaymentGatewayEnabled =>
      _appSettingsManager.settings?.paymentGatewayEnabled ?? true;

  int get initialAmount =>
      _appSettingsManager.settings?.initialPrice ??
      AppConstants.kDefaultInitialPrintPrice;

  SessionDiscount? get appliedDiscount => _appliedDiscount;
  String? get couponError => _couponError;
  bool get couponBusy => _couponBusy;

  int get chargeAmount {
    final d = _appliedDiscount;
    if (d == null) return initialAmount;
    return d.chargeAmount;
  }

  bool get isDeadPollingFallbackVisible {
    if (_paymentOutcomeHandled) return false;
    if (_fcmPaymentPushSuccess != null) return false;
    return _paymentIdConsecutiveFailureTicks >= 10 &&
        _sessionConsecutiveFailureTicks >= 10;
  }

  @visibleForTesting
  void setPollingFailureStreaksForTest({
    required int paymentFailures,
    required int sessionFailures,
  }) {
    _paymentIdConsecutiveFailureTicks = paymentFailures;
    _sessionConsecutiveFailureTicks = sessionFailures;
    notifyListeners();
  }

  @visibleForTesting
  Future<void> runPaymentPollTickForTest(Timer timer) =>
      _onPaymentPollTick(timer);

  @visibleForTesting
  Future<void> runSessionPollTickForTest(Timer timer, String sessionId) =>
      _onSessionPollTick(timer, sessionId);

  @visibleForTesting
  void setSessionPollTicksForTest(int ticks) => _sessionPollTicks = ticks;

  void stopPaymentPolling() {
    _paymentIdPollTimer?.cancel();
    _paymentIdPollTimer = null;
    _sessionPollTimer?.cancel();
    _sessionPollTimer = null;
  }

  Future<void> retryLoadPaymentQr() {
    _paymentInitiateAttempts = 0;
    _paymentInitiateGeneration += 1;
    _activePaymentId = null;
    _paymentInitError = null;
    return loadPaymentQr(force: true);
  }

  Future<void> loadPaymentQr({
    bool force = false,
    PhotoModel? photoForSessionSync,
  }) async {
    if (_paymentInitInProgress && !force) return;
    if (!force && _shouldSkipPaymentInitiate()) return;
    final sessionId = _sessionManager.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      _paymentInitError = 'No session for payment. Go back and try again.';
      notifyListeners();
      return;
    }

    final generation = ++_paymentInitiateGeneration;
    _paymentInitInProgress = true;
    _paymentInitError = null;
    if (force) {
      _paymentLink = null;
      _qrImageUrl = null;
      _upiLink = null;
      _activePaymentId = null;
    }
    stopPaymentPolling();
    _paymentIdPollTicks = 0;
    _sessionPollTicks = 0;
    _paymentIdNullStreak = 0;
    _sessionNullStreak = 0;
    _paymentIdConsecutiveFailureTicks = 0;
    _sessionConsecutiveFailureTicks = 0;
    _paymentOutcomeHandled = false;
    notifyListeners();

    try {
      if (photoForSessionSync != null) {
        final photoSync = await ensureSessionPhotoOnServer(
          sessionId: sessionId,
          photo: photoForSessionSync,
          sessionManager: _sessionManager,
          apiService: _apiService,
        );
        if (_disposed || generation != _paymentInitiateGeneration) return;
        if (!photoSync.isReady) {
          _paymentInitError =
              photoSync.errorMessage ?? AppStrings.sessionPhotoSyncFailed;
          return;
        }
      }

      final fcmToken = await FcmService.getToken();
      final result = await _apiService.initiatePayment(
        sessionId: sessionId,
        amount: chargeAmount,
        type: 'INITIAL',
        fcmToken: fcmToken ?? '',
      );
      if (generation != _paymentInitiateGeneration) return;
      _applyPaymentInitiateResult(result);
      if (!hasPaymentQrPayload &&
          _activePaymentId != null &&
          _paymentInitiateAttempts < 1) {
        _paymentInitiateAttempts += 1;
        _paymentInitInProgress = false;
        notifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 900));
        if (_disposed) return;
        return loadPaymentQr(force: true);
      }
      if (!hasPaymentQrPayload) {
        _paymentInitError =
            'Could not load UPI QR from the server. Tap Retry below or ask staff.';
      } else {
        _paymentInitError = null;
      }
      if (_activePaymentId != null) {
        _startPaymentStatusPolling();
      }
      _startSessionApprovalPolling(sessionId);
    } on ApiException catch (e) {
      _paymentInitError = e.message;
    } catch (e, st) {
      _paymentInitError = 'Payment setup failed: $e';
      unawaited(
        reportIssue(
          'Pre-payment setup failed',
          e,
          st,
          extraInfo: {'source': 'pre_payment_init'},
        ),
      );
    } finally {
      if (generation == _paymentInitiateGeneration) {
        _paymentInitInProgress = false;
        notifyListeners();
      }
    }
  }

  bool _shouldSkipPaymentInitiate() {
    final existingId = _activePaymentId?.trim();
    if (existingId == null || existingId.isEmpty) return false;
    return hasPaymentQrPayload;
  }

  void _applyPaymentInitiateResult(PaymentInitiateResult result) {
    _paymentLink = result.paymentLink;
    _qrImageUrl = result.qrImageUrl;
    _upiLink = result.upiLink;
    final pid = result.id.trim();
    _activePaymentId = pid.isNotEmpty ? pid : null;
    if (hasPaymentQrPayload) {
      _paymentInitError = null;
    }
  }

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
      t.cancel();
      return;
    }

    Map<String, dynamic>? raw;
    try {
      raw = await _apiService.fetchSession(sessionId);
    } catch (_) {
      raw = null;
    }
    if (_disposed || _paymentOutcomeHandled) {
      t.cancel();
      return;
    }
    if (raw == null) {
      if (++_sessionNullStreak >= 8) {
        // Keep polling; UI may show stuck fallback.
      }
      _sessionConsecutiveFailureTicks += 1;
      if (_sessionConsecutiveFailureTicks == 10) notifyListeners();
      return;
    }
    _sessionNullStreak = 0;
    _sessionConsecutiveFailureTicks = 0;

    final verdict = paymentVerdictFromSession(raw);
    switch (verdict) {
      case PaymentPollVerdict.approved:
        t.cancel();
        await onFcmPaymentPush(
          PaymentPushPayload(
            type: PaymentPushCoordinator.typeApproved,
            paymentId: sessionId,
            title: AppStrings.paymentConfirmedTitle,
            body: 'Payment approved. Starting AI generation…',
          ),
        );
      case PaymentPollVerdict.failed:
        t.cancel();
        await onFcmPaymentPush(
          PaymentPushPayload(
            type: PaymentPushCoordinator.typeFailed,
            paymentId: sessionId,
            title: AppStrings.paymentNotCompletedTitle,
            body: AppStrings.paymentFailedRetryBody,
          ),
        );
      case PaymentPollVerdict.pending:
      case null:
        break;
    }
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
    final sessionId = _sessionManager.sessionId?.trim();

    Map<String, dynamic>? raw;
    try {
      raw = await _apiService.fetchPaymentStatus(id, sessionId: sessionId);
    } catch (_) {
      raw = null;
    }
    if (_disposed || _paymentOutcomeHandled) {
      t.cancel();
      return;
    }
    if (raw == null) {
      if (++_paymentIdNullStreak >= 8) {
        // Keep polling.
      }
      _paymentIdConsecutiveFailureTicks += 1;
      if (_paymentIdConsecutiveFailureTicks == 10) notifyListeners();
      return;
    }
    _paymentIdNullStreak = 0;
    _paymentIdConsecutiveFailureTicks = 0;

    final verdict = paymentVerdictFromPaymentStatusResponse(raw);
    switch (verdict) {
      case PaymentPollVerdict.approved:
        t.cancel();
        await onFcmPaymentPush(
          PaymentPushPayload(
            type: PaymentPushCoordinator.typeApproved,
            paymentId: id,
            title: AppStrings.paymentConfirmedTitle,
            body: 'Payment approved. Starting AI generation…',
          ),
        );
      case PaymentPollVerdict.failed:
        t.cancel();
        await onFcmPaymentPush(
          PaymentPushPayload(
            type: PaymentPushCoordinator.typeFailed,
            paymentId: id,
            title: AppStrings.paymentNotCompletedTitle,
            body: AppStrings.paymentFailedRetryBody,
          ),
        );
      case PaymentPollVerdict.pending:
      case null:
        break;
    }
  }

  bool _tryClaimPaymentOutcome() {
    if (_paymentOutcomeHandled) return false;
    _paymentOutcomeHandled = true;
    stopPaymentPolling();
    return true;
  }

  Future<void> refreshPaymentPolling() async {
    if (_paymentOutcomeHandled) return;
    final sessionId = _sessionManager.sessionId;
    if (sessionId == null || sessionId.trim().isEmpty) return;

    _paymentIdConsecutiveFailureTicks = 0;
    _sessionConsecutiveFailureTicks = 0;
    _paymentIdNullStreak = 0;
    _sessionNullStreak = 0;
    notifyListeners();

    try {
      final raw = await _apiService.fetchSession(sessionId);
      if (_disposed) return;
      if (raw != null) {
        final verdict = paymentVerdictFromSession(raw);
        if (verdict == PaymentPollVerdict.approved) {
          await onFcmPaymentPush(
            PaymentPushPayload(
              type: PaymentPushCoordinator.typeApproved,
              paymentId: sessionId,
              title: AppStrings.paymentConfirmedTitle,
              body: 'Payment approved. Starting AI generation…',
            ),
          );
          return;
        }
        if (verdict == PaymentPollVerdict.failed) {
          await onFcmPaymentPush(
            PaymentPushPayload(
              type: PaymentPushCoordinator.typeFailed,
              paymentId: sessionId,
              title: AppStrings.paymentNotCompletedTitle,
              body: AppStrings.paymentFailedRetryBody,
            ),
          );
          return;
        }
      }
    } catch (_) {
      // ignore
    }
    if (_disposed) return;

    _startSessionApprovalPolling(sessionId);
    if (_activePaymentId != null && _activePaymentId!.trim().isNotEmpty) {
      _startPaymentStatusPolling();
    }
  }

  Future<void> onFcmPaymentPush(PaymentPushPayload payload) async {
    if (!payload.isApproved && !payload.isFailed) return;
    if (!_tryClaimPaymentOutcome()) return;

    if (payload.isApproved) {
      _fcmPaymentPushSuccess = true;
      _fcmPaymentStatusDetail = payload.body ??
          'Payment approved. Starting AI generation…';
      notifyListeners();
      onApproved?.call();
      return;
    }
    _fcmPaymentPushSuccess = false;
    _fcmPaymentStatusDetail =
        payload.body ?? AppStrings.paymentFailedRetryBody;
    notifyListeners();
  }


  Future<void> applyCoupon(String code) async {
    final sessionId = _sessionManager.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      _couponError = 'No session for coupon';
      notifyListeners();
      return;
    }
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      _couponError = 'Enter a coupon code';
      notifyListeners();
      return;
    }
    final subtotal = initialAmount;
    if (subtotal <= 0) {
      _couponError = 'Nothing to discount';
      notifyListeners();
      return;
    }
    _couponBusy = true;
    _couponError = null;
    notifyListeners();
    try {
      final raw = await _apiService.applySessionDiscount(
        sessionId: sessionId,
        code: trimmed,
        subtotal: subtotal,
      );
      _appliedDiscount = SessionDiscount.fromApplyResponse(raw);
      _couponError = null;
      await loadPaymentQr(force: true);
    } on ApiException catch (e) {
      _couponError = e.message;
    } catch (e) {
      _couponError = 'Could not apply coupon: $e';
    } finally {
      _couponBusy = false;
      notifyListeners();
    }
  }

  Future<void> unapplyCoupon() async {
    final sessionId = _sessionManager.sessionId;
    if (sessionId == null || sessionId.isEmpty) return;
    _couponBusy = true;
    _couponError = null;
    notifyListeners();
    try {
      await _apiService.unapplySessionDiscount(sessionId: sessionId);
      _appliedDiscount = null;
      await loadPaymentQr(force: true);
    } on ApiException catch (e) {
      _couponError = e.message;
    } catch (e) {
      _couponError = 'Could not remove coupon: $e';
    } finally {
      _couponBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stopPaymentPolling();
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }
}
