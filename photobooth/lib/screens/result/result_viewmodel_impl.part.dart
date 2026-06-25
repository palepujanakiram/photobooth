part of 'result_viewmodel.dart';

mixin _ResultViewModelImpl on ChangeNotifier {
  ResultViewModel get _r => this as ResultViewModel;

  /// Loads UPI payment link from POST /api/payment/initiate and exposes it for QR display.
  Future<void> loadPaymentQr({String? customerPhone}) async {
    if (_r._paymentInitInProgress) return;
    final existingId = _r._activePaymentId?.trim();
    if (existingId != null && existingId.isNotEmpty) return;
    final sessionId = _r._sessionManager.sessionId;
    if (sessionId == null || sessionId.isEmpty) {
      _r._paymentInitError = 'No session for payment. Go back and try again.';
      notifyListeners();
      return;
    }

    _r._paymentInitInProgress = true;
    _r._paymentInitError = null;
    _r._paymentLink = null;
    _r._qrImageUrl = null;
    _r._upiLink = null;
    _r._activePaymentId = null;
    _r._paymentIdPollTimer?.cancel();
    _r._sessionPollTimer?.cancel();
    _r._paymentIdPollTicks = 0;
    _r._sessionPollTicks = 0;
    _r._paymentIdNullStreak = 0;
    _r._sessionNullStreak = 0;
    _r._paymentIdConsecutiveFailureTicks = 0;
    _r._sessionConsecutiveFailureTicks = 0;
    _r._paymentOutcomeHandled = false;
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
      final result = await _r._apiService.initiatePayment(
        sessionId: sessionId,
        amount: _r.totalPrice,
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
      _r._paymentLink = result.paymentLink;
      _r._qrImageUrl = result.qrImageUrl;
      _r._upiLink = result.upiLink;
      final pid = result.id.trim();
      _r._activePaymentId = pid.isNotEmpty ? pid : null;
      if (_r._activePaymentId != null) {
        _startPaymentStatusPolling();
      }
      // Backup: also poll session by sessionId (React Query style) so approval can
      // still be detected even if paymentId polling/FCM is missing.
      _startSessionApprovalPolling(sessionId);
    } on ApiException catch (e) {
      _r._paymentInitError = e.message;
    } catch (e) {
      _r._paymentInitError = 'Payment setup failed: $e';
    } finally {
      _r._paymentInitInProgress = false;
      notifyListeners();
    }
  }

  /// Kiosk polling backup cadence: every 3 seconds.
  static const _paymentPollInterval = Duration(seconds: 3);

  void _startPaymentStatusPolling() {
    _r._paymentIdPollTimer?.cancel();
    _r._paymentIdPollTicks = 0;
    _r._paymentIdNullStreak = 0;
    _r._paymentIdConsecutiveFailureTicks = 0;
    _r._paymentIdPollTimer = Timer.periodic(
      _paymentPollInterval,
      _onPaymentPollTick,
    );
  }

  void _startSessionApprovalPolling(String sessionId) {
    _r._sessionPollTimer?.cancel();
    _r._sessionPollTicks = 0;
    _r._sessionNullStreak = 0;
    _r._sessionConsecutiveFailureTicks = 0;
    _r._sessionPollTimer = Timer.periodic(
      _paymentPollInterval,
      (t) => _onSessionPollTick(t, sessionId),
    );
  }

  Future<void> _onSessionPollTick(Timer t, String sessionId) async {
    if (_r._paymentOutcomeHandled) {
      t.cancel();
      return;
    }
    if (++_r._sessionPollTicks > 180) {
      // 12 minutes max.
      t.cancel();
      return;
    }

    Map<String, dynamic>? raw;
    try {
      raw = await _r._apiService.fetchSession(sessionId);
    } catch (_) {
      raw = null;
    }
    if (_r._disposed) {
      t.cancel();
      return;
    }
    if (_r._paymentOutcomeHandled) {
      t.cancel();
      return;
    }
    if (raw == null) {
      if (++_r._sessionNullStreak >= 8) {
        // Keep polling, but allow UI to surface a "stuck" fallback.
      }
      _r._sessionConsecutiveFailureTicks += 1;
      if (_r._sessionConsecutiveFailureTicks == 10) notifyListeners();
      return;
    }
    _r._sessionNullStreak = 0;
    _r._sessionConsecutiveFailureTicks = 0;

    final verdict = _verdictFromSession(raw);
    switch (verdict) {
      case _PollVerdict.approved:
        t.cancel();
        await onFcmPaymentPush(
          PaymentPushPayload(
            type: PaymentPushCoordinator.typeApproved,
            paymentId: sessionId,
            title: AppStrings.paymentConfirmedTitle,
            body: 'Payment approved. Printing...',
          ),
        );
      case _PollVerdict.failed:
        t.cancel();
        await onFcmPaymentPush(
          PaymentPushPayload(
            type: PaymentPushCoordinator.typeFailed,
            paymentId: sessionId,
            title: AppStrings.paymentNotCompletedTitle,
            body: AppStrings.paymentFailedRetryBody,
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
    if (_r._paymentOutcomeHandled) {
      t.cancel();
      return;
    }
    if (++_r._paymentIdPollTicks > 90) {
      t.cancel();
      return;
    }
    final id = _r._activePaymentId;
    if (id == null || id.isEmpty) {
      t.cancel();
      return;
    }
    final sessionId = _r._sessionManager.sessionId?.trim();

    Map<String, dynamic>? raw;
    try {
      raw = await _r._apiService.fetchPaymentStatus(
        id,
        sessionId: sessionId,
      );
    } catch (_) {
      raw = null;
    }
    if (_r._disposed) {
      t.cancel();
      return;
    }
    if (_r._paymentOutcomeHandled) {
      t.cancel();
      return;
    }
    if (raw == null) {
      if (++_r._paymentIdNullStreak >= 8) {
        // Keep polling, but allow UI to surface a "stuck" fallback.
      }
      _r._paymentIdConsecutiveFailureTicks += 1;
      if (_r._paymentIdConsecutiveFailureTicks == 10) notifyListeners();
      return;
    }
    _r._paymentIdNullStreak = 0;
    _r._paymentIdConsecutiveFailureTicks = 0;

    final verdict = _verdictFromPaymentStatusResponse(raw);
    switch (verdict) {
      case _PollVerdict.approved:
        t.cancel();
        await onFcmPaymentPush(
          PaymentPushPayload(
            type: PaymentPushCoordinator.typeApproved,
            paymentId: id,
            title: AppStrings.paymentConfirmedTitle,
            body: 'Payment approved. Proceed to print your photo.',
          ),
        );
      case _PollVerdict.failed:
        t.cancel();
        await onFcmPaymentPush(
          PaymentPushPayload(
            type: PaymentPushCoordinator.typeFailed,
            paymentId: id,
            title: AppStrings.paymentNotCompletedTitle,
            body: AppStrings.paymentFailedRetryBody,
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
    if (_r._paymentOutcomeHandled) return false;
    _r._paymentOutcomeHandled = true;
    _r._paymentIdPollTimer?.cancel();
    _r._paymentIdPollTimer = null;
    _r._sessionPollTimer?.cancel();
    _r._sessionPollTimer = null;
    return true;
  }

  /// CTA: force a client-side refresh of polling state.
  ///
  /// Does not re-initiate payment (no new payment id); it just resets failure
  /// streaks and restarts the timers so operators can recover from transient
  /// connectivity / backend hiccups.
  Future<void> refreshPaymentPolling() async {
    if (_r._paymentOutcomeHandled) return;
    final sessionId = _r._sessionManager.sessionId;
    if (sessionId == null || sessionId.trim().isEmpty) return;

    _r._paymentIdConsecutiveFailureTicks = 0;
    _r._sessionConsecutiveFailureTicks = 0;
    _r._paymentIdNullStreak = 0;
    _r._sessionNullStreak = 0;
    notifyListeners();

    // Fire a one-shot refresh first (gives instant feedback), then restart cadence.
    try {
      final raw = await _r._apiService.fetchSession(sessionId);
      if (_r._disposed) return;
      if (raw != null) {
        final verdict = _verdictFromSession(raw);
        if (verdict == _PollVerdict.approved) {
          await onFcmPaymentPush(
            PaymentPushPayload(
              type: PaymentPushCoordinator.typeApproved,
              paymentId: sessionId,
              title: AppStrings.paymentConfirmedTitle,
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
    if (_r._disposed) return;

    _startSessionApprovalPolling(sessionId);
    if (_r._activePaymentId != null && _r._activePaymentId!.trim().isNotEmpty) {
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
      _r._fcmPaymentPushSuccess = true;
      _r._fcmPaymentStatusDetail = _fcmApprovedDetailText(payload);
      notifyListeners();

      // Fire-and-forget: queue receipt + WhatsApp send in parallel with print.
      // ensurePostPaymentShareArtifacts is internally idempotent
      // (_r._postPaymentSharePrepared) so calling it again from
      // _navigateToThankYouIfEligible is a no-op.
      unawaited(ensurePostPaymentShareArtifacts());

      try {
        await silentPrintToNetwork().timeout(const Duration(minutes: 2));
      } on TimeoutException {
        _r._errorMessage =
            'Printing is taking longer than expected. Please check the printer connection and try again.';
      }
      notifyListeners();
      return;
    }
    _r._fcmPaymentPushSuccess = false;
    _r._fcmPaymentStatusDetail = _fcmFailedDetailText(payload);
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
    final sessionId = _r._sessionManager.sessionId;
    if (sessionId == null) return;
    await _r._apiService.deleteSession(sessionId);
    await endPhotoboothCustomerSessionLogged('result: deleteSession');
  }

  /// Kiosk privacy wipe: clears local session + temp image files so the next user cannot access prior photos.
  ///
  /// This does **not** delete anything on the server (transactions/audit can remain).
  Future<void> privacyWipeLocal() async {
    _r._paymentIdPollTimer?.cancel();
    _r._paymentIdPollTimer = null;
    _r._sessionPollTimer?.cancel();
    _r._sessionPollTimer = null;
    stopWhatsappDeliveryPolling();
    _r._downloadedFiles.clear();
    await endPhotoboothCustomerSessionLogged('result: privacyWipeLocal');
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
    if (_r._whatsappDeliveryStatus == next &&
        (detail == null || detail == _r._whatsappDeliveryDetail)) {
      return;
    }
    _r._whatsappDeliveryStatus = next;
    if (detail != null) {
      _r._whatsappDeliveryDetail = detail;
    }
    notifyListeners();
  }

  void applyWhatsappStatusPush(WhatsAppStatusPayload payload) {
    final sid = _r._sessionManager.sessionId?.trim() ?? '';
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

  Future<bool> refreshWhatsappDeliveryStatusFromSession() async {
    final sid = _r._sessionManager.sessionId;
    if (sid == null || sid.trim().isEmpty) return false;
    Map<String, dynamic>? raw;
    try {
      raw = await _r._apiService.fetchSession(sid);
    } catch (_) {
      raw = null;
    }
    if (_r._disposed) return false;
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
    if (!_r.effectiveWhatsappOptIn) return;
    stopWhatsappDeliveryPolling();
    _r._whatsappPollTicks = 0;

    var consecutiveFailures = 0;
    Duration nextDelay = const Duration(seconds: 3);

    void scheduleNext() {
      _r._whatsappPollTimer?.cancel();
      _r._whatsappPollTimer = Timer(nextDelay, () async {
        if (++_r._whatsappPollTicks > 120) {
          stopWhatsappDeliveryPolling();
          return;
        }

        final ok = await refreshWhatsappDeliveryStatusFromSession();
        if (_r._whatsappPollTimer == null) {
          return; // stopped due to terminal status
        }

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
    _r._whatsappPollTimer?.cancel();
    _r._whatsappPollTimer = null;
    _r._whatsappPollTicks = 0;
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

    if (url != null) _r._receiptShareUrl = url;
    if (longUrl != null) _r._receiptShareLongUrl = longUrl;
    if (exp != null) _r._receiptShareExpiresAt = exp;
    if (pdf != null) _r._receiptPdfUrl = pdf;

    // Trust the server's explicit `whatsappQueued` boolean (true OR false).
    // Backend now returns this on every receipt response. Only fall back to
    // the older `whatsappRequested` field if `whatsappQueued` isn't present.
    final waQueuedRaw = raw['whatsappQueued'] ?? raw['whatsapp_queued'];
    if (waQueuedRaw is bool) {
      _r._whatsappQueued = waQueuedRaw;
    } else {
      final legacy =
          raw['whatsappRequested'] == true || raw['whatsapp_requested'] == true;
      if (legacy) _r._whatsappQueued = true;
    }

    final skipReason = _firstNonEmptyString(raw['whatsappSkipReason']) ??
        _firstNonEmptyString(raw['whatsapp_skip_reason']);
    if (skipReason != null) {
      _r._whatsappSkipReason = skipReason.toLowerCase();
    }

    final pdfErr = _firstNonEmptyString(raw['pdfError']) ??
        _firstNonEmptyString(raw['pdf_error']);
    if (pdfErr != null) {
      _r._pdfError = pdfErr;
    }

    final st = _pickWhatsappDeliveryStatus(raw);
    if (st != null) {
      _r._whatsappDeliveryStatus = st;
    }
  }

  /// After payment approval: request canonical receipt/share link + mint kiosk fallback.
  ///
  /// Concurrent-safe: callers from both [onFcmPaymentPush] and the navigation path
  /// share a single in-flight Future, so the receipt POST never fires twice.
  Future<void> ensurePostPaymentShareArtifacts() {
    if (_r._postPaymentSharePrepared) return Future<void>.value();
    final inflight = _r._postPaymentInflight;
    if (inflight != null) return inflight;
    final fut = _runPostPaymentShareArtifacts();
    _r._postPaymentInflight = fut;
    return fut.whenComplete(() {
      _r._postPaymentInflight = null;
    });
  }

  Future<void> _runPostPaymentShareArtifacts() async {
    final sessionId = _r._sessionManager.sessionId;
    if (sessionId == null || sessionId.trim().isEmpty) {
      _r._postPaymentSharePrepared = true;
      return;
    }

    await _mintKioskFallbackForPostPayment();
    if (_r._disposed) return;

    await _postSessionReceiptForPostPayment(sessionId);
    if (_r._disposed) return;

    applyKioskFallbackWhenReceiptShareEmpty(
      KioskReceiptShareFallback(
        receiptShareUrl: _r._receiptShareUrl,
        kioskFallbackShareUrl: _r._kioskFallbackShareUrl,
        setReceiptShareUrl: (u) => _r._receiptShareUrl = u,
        receiptShareLongUrl: _r._receiptShareLongUrl,
        kioskFallbackShareLongUrl: _r._kioskFallbackShareLongUrl,
        setReceiptShareLongUrl: (u) => _r._receiptShareLongUrl = u,
        receiptShareExpiresAt: _r._receiptShareExpiresAt,
        kioskFallbackShareExpiresAt: _r._kioskFallbackShareExpiresAt,
        setReceiptShareExpiresAt: (t) => _r._receiptShareExpiresAt = t,
      ),
    );

    _r._postPaymentSharePrepared = true;
    await refreshWhatsappDeliveryStatusFromSession();
    notifyListeners();
  }

  Future<void> _mintKioskFallbackForPostPayment() async {
    try {
      final kiosk = await mintCustomerShareLink();
      if (_r._disposed) return;
      if (kiosk != null && kiosk.isValid) {
        _r._kioskFallbackShareUrl = kiosk.url;
        _r._kioskFallbackShareLongUrl = kiosk.longUrl;
        _r._kioskFallbackShareExpiresAt = kiosk.expiresAt;
      }
    } catch (e, st) {
      AppLogger.debug('post-payment kiosk share mint failed: $e\n$st');
    }
  }

  Future<void> _postSessionReceiptForPostPayment(String sessionId) async {
    try {
      final fcmToken = kIsWeb ? null : await FcmService.getToken();
      if (_r._disposed) return;
      final receipt = await _postSessionReceiptWithRetry(
        sessionId: sessionId,
        fcmToken: fcmToken,
      );
      if (_r._disposed) return;
      if (receipt != null) {
        _r._receiptResponseReceived = true;
        _ingestReceiptShareFields(receipt);
      }
    } catch (e, st) {
      AppLogger.debug('postSessionReceipt failed (outer): $e\n$st');
    }
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
        return await _r._apiService.postSessionReceipt(
          sessionId: sessionId,
          customerName: _r._customerName,
          customerPhone: _r._customerPhone,
          whatsappOptIn: _r.effectiveWhatsappOptIn,
          transactionRef: _r._activePaymentId,
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
        'transactionRef': _r._activePaymentId,
        'whatsappOptIn': _r.effectiveWhatsappOptIn,
        'hasCustomerPhone': (_r._customerPhone?.trim().isNotEmpty ?? false),
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
    final sessionId = _r._sessionManager.sessionId;
    if (sessionId == null || sessionId.trim().isEmpty) return null;
    final kioskCode = await _r._kioskManager.getKioskCode();
    if (kioskCode == null || kioskCode.trim().isEmpty) return null;

    try {
      final raw = await _r._apiService.createKioskShareLink(
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
    if (_r._isDownloading) return false;

    _r._isDownloading = true;
    _r._downloadingForAction = forAction;
    _r._downloadMessage = 'Preparing images...';
    notifyListeners();

    try {
      for (int i = 0; i < _r._generatedImages.length; i++) {
        final image = _r._generatedImages[i];
        if (!_r._downloadedFiles.containsKey(image.id)) {
          _r._downloadMessage =
              'Downloading image ${i + 1} of ${_r._generatedImages.length}...';
          notifyListeners();

          final downloaded = await _r._apiService.downloadImageToTemp(
            image.imageUrl,
            onProgress: (message) {
              _r._downloadMessage = message;
              notifyListeners();
            },
          );
          _r._downloadedFiles[image.id] = downloaded;
        }
      }

      _r._isDownloading = false;
      _r._downloadingForAction = '';
      notifyListeners();
      return true;
    } catch (e) {
      _r._errorMessage = 'Failed to download images: $e';
      _r._isDownloading = false;
      _r._downloadingForAction = '';
      notifyListeners();
      return false;
    }
  }

  /// Get downloaded files list
  List<XFile> get _downloadedFilesList {
    return _r._generatedImages
        .where((img) => _r._downloadedFiles.containsKey(img.id))
        .map((img) => _r._downloadedFiles[img.id]!)
        .toList();
  }

  /// Silent print all images to network printer
  Future<void> silentPrintToNetwork() async {
    if (_r._printerHost.isEmpty) {
      _r._errorMessage = 'Please enter a printer address';
      notifyListeners();
      return;
    }

    // Download files first if needed
    if (!kIsWeb && _downloadedFilesList.length != _r._generatedImages.length) {
      final success = await _ensureAllFilesDownloaded('silent');
      if (!success) return;
    }

    _r._isSilentPrinting = true;
    _r._errorMessage = null;
    notifyListeners();

    try {
      final files = _downloadedFilesList;
      for (int i = 0; i < files.length; i++) {
        await _r._printService.printImageToNetworkPrinter(
          files[i],
          printerHost: _r._printerHost,
          printerPort: _r.effectivePrinterPort,
          printSize: _r._printOrientation.printSize,
        );
      }
    } on PrintException catch (e) {
      _r._errorMessage = e.message;
    } catch (e) {
      _r._errorMessage = 'Failed to print: $e';
    } finally {
      _r._isSilentPrinting = false;
      notifyListeners();
    }
  }

  Future<void> _shareImagesOnWeb({Rect? sharePositionOrigin}) async {
    final urls = _r._generatedImages
        .map((e) => e.imageUrl)
        .where((u) => u.trim().isNotEmpty)
        .toList();
    if (urls.isEmpty) {
      _r._errorMessage = 'No images to share';
      notifyListeners();
      return;
    }
    _r._isSharing = true;
    _r._errorMessage = null;
    notifyListeners();
    try {
      _r._errorMessage = await shareGeneratedImageUrlsOnWeb(
        urls: urls,
        shareText: _r._shareService.shareText,
        sharePositionOrigin: sharePositionOrigin,
      );
    } finally {
      _r._isSharing = false;
      notifyListeners();
    }
  }

  /// Print all images using system print dialog
  Future<void> printWithDialog() async {
    // Download files first if needed
    if (!kIsWeb && _downloadedFilesList.length != _r._generatedImages.length) {
      final success = await _ensureAllFilesDownloaded('dialog');
      if (!success) return;
    }

    _r._isDialogPrinting = true;
    _r._errorMessage = null;
    notifyListeners();

    try {
      final files = _downloadedFilesList;
      for (int i = 0; i < files.length; i++) {
        await _r._printService.printImageWithDialog(files[i]);
      }
    } on PrintException catch (e) {
      _r._errorMessage = e.message;
    } catch (e) {
      _r._errorMessage = 'Failed to print: $e';
    } finally {
      _r._isDialogPrinting = false;
      notifyListeners();
    }
  }

  /// Share all images
  Future<void> shareImages({Rect? sharePositionOrigin}) async {
    if (kIsWeb) {
      await _shareImagesOnWeb(sharePositionOrigin: sharePositionOrigin);
      return;
    }

    // Download files first if needed
    if (_downloadedFilesList.length != _r._generatedImages.length) {
      final success = await _ensureAllFilesDownloaded('share');
      if (!success) return;
    }

    _r._isSharing = true;
    _r._errorMessage = null;
    notifyListeners();

    try {
      final files = _downloadedFilesList;
      if (files.isEmpty) {
        throw ShareException(
            'No images to share (download did not produce any files)');
      }
      // Share all images using the multiple images method
      await _r._shareService.shareMultipleImages(
        files,
        text:
            'Check out my ${files.length} AI generated photo${files.length > 1 ? 's' : ''}!',
        sharePositionOrigin: sharePositionOrigin,
      );
    } on ShareException catch (e) {
      _r._errorMessage = e.message;
    } catch (e) {
      _r._errorMessage = 'Failed to share: $e';
    } finally {
      _r._isSharing = false;
      notifyListeners();
    }
  }
}
