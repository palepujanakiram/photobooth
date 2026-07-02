import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';
import '../utils/print_orientation.dart';
import 'error_reporting/error_reporting_manager.dart';
import 'kiosk_session_auth.dart';

/// Session data model matching API response
class SessionData {
  final String id; // sessionId from API response
  final bool termsAccepted;
  final DateTime termsAcceptedAt;
  final String? termsAcceptedIp;
  final String? termsVersion;
  final int attemptsUsed;
  final List<dynamic> generatedImages;
  final DateTime expiresAt;
  final String? kioskId;
  final String? kioskLocation;
  final String?
      userImageUrl; // Base64 encoded image from PATCH /api/sessions/{sessionId}
  final String? selectedThemeId; // Theme ID selected by user
  final String? selectedCategoryId; // Category ID of selected theme
  /// Frame id, `"none"` if customer declined, or null if unset / auto-resolve later.
  final String? selectedFrameId;
  /// Opaque token from session create; sent as `X-Kiosk-Session-Token` on protected routes.
  final String? kioskAuthToken;
  /// Authoritative person count from `/api/preprocess-image` (used for theme filtering).
  final int? personCount;
  /// Customer print layout preference (`portrait` | `landscape`).
  final String? printOrientation;

  SessionData({
    required this.id,
    required this.termsAccepted,
    required this.termsAcceptedAt,
    this.termsAcceptedIp,
    this.termsVersion,
    required this.attemptsUsed,
    required this.generatedImages,
    required this.expiresAt,
    this.kioskId,
    this.kioskLocation,
    this.userImageUrl,
    this.selectedThemeId,
    this.selectedCategoryId,
    this.selectedFrameId,
    this.kioskAuthToken,
    this.personCount,
    this.printOrientation,
  });

  SessionData copyWith({
    int? personCount,
    String? kioskAuthToken,
    String? printOrientation,
    int? attemptsUsed,
  }) {
    return SessionData(
      id: id,
      termsAccepted: termsAccepted,
      termsAcceptedAt: termsAcceptedAt,
      termsAcceptedIp: termsAcceptedIp,
      termsVersion: termsVersion,
      attemptsUsed: attemptsUsed ?? this.attemptsUsed,
      generatedImages: generatedImages,
      expiresAt: expiresAt,
      kioskId: kioskId,
      kioskLocation: kioskLocation,
      userImageUrl: userImageUrl,
      selectedThemeId: selectedThemeId,
      selectedCategoryId: selectedCategoryId,
      selectedFrameId: selectedFrameId,
      kioskAuthToken: kioskAuthToken ?? this.kioskAuthToken,
      personCount: personCount ?? this.personCount,
      printOrientation: printOrientation ?? this.printOrientation,
    );
  }

  /// Get sessionId (alias for id)
  String get sessionId => id;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'termsAccepted': termsAccepted,
      'termsAcceptedAt': termsAcceptedAt.toIso8601String(),
      'termsAcceptedIp': termsAcceptedIp,
      'termsVersion': termsVersion,
      'attemptsUsed': attemptsUsed,
      'generatedImages': generatedImages,
      'expiresAt': expiresAt.toIso8601String(),
      'kioskId': kioskId,
      'kioskLocation': kioskLocation,
      'userImageUrl': userImageUrl,
      'selectedThemeId': selectedThemeId,
      'selectedCategoryId': selectedCategoryId,
      'selectedFrameId': selectedFrameId,
      if (kioskAuthToken != null) 'kioskAuthToken': kioskAuthToken,
      if (personCount != null) 'personCount': personCount,
      if (printOrientation != null) 'printOrientation': printOrientation,
    };
  }

  static String? _printOrientationFromJson(Map<String, dynamic> json) {
    final direct = PrintOrientation.tryParse(json['printOrientation']?.toString());
    if (direct != null) return direct.apiValue;
    final framing = json['framingMetadata'];
    if (framing is Map) {
      final fromFraming =
          PrintOrientation.tryParse(framing['orientation']?.toString());
      if (fromFraming != null) return fromFraming.apiValue;
    }
    return null;
  }

  static int? _personCountFromJson(Map<String, dynamic> json) {
    final v = json['personCount'];
    if (v is int && v > 0) return v;
    if (v is num && v > 0) return v.round();
    return null;
  }

  static String _requireString(Map<String, dynamic> json, String key) {
    final v = json[key];
    if (v is String && v.trim().isNotEmpty) return v;
    throw FormatException('Missing/invalid required field "$key"');
  }

  static DateTime _requireDateTime(Map<String, dynamic> json, String key) {
    final raw = json[key];
    if (raw is! String || raw.trim().isEmpty) {
      throw FormatException('Missing/invalid required field "$key"');
    }
    return DateTime.parse(raw);
  }

  factory SessionData.fromJson(Map<String, dynamic> json) {
    return SessionData(
      id: _requireString(json, 'id'),
      termsAccepted: json['termsAccepted'] as bool? ?? false,
      termsAcceptedAt: _requireDateTime(json, 'termsAcceptedAt'),
      termsAcceptedIp: json['termsAcceptedIp'] as String?,
      termsVersion: json['termsVersion'] as String?,
      attemptsUsed: json['attemptsUsed'] as int? ?? 0,
      generatedImages: json['generatedImages'] as List<dynamic>? ?? [],
      expiresAt: _requireDateTime(json, 'expiresAt'),
      kioskId: json['kioskId'] as String?,
      kioskLocation: json['kioskLocation'] as String?,
      userImageUrl: json['userImageUrl'] as String?,
      selectedThemeId: json['selectedThemeId'] as String?,
      selectedCategoryId: json['selectedCategoryId'] as String?,
      selectedFrameId: json['selectedFrameId'] as String?,
      kioskAuthToken: parseKioskAuthToken(json),
      personCount: _personCountFromJson(json),
      printOrientation: _printOrientationFromJson(json),
    );
  }
}

/// Singleton class responsible for managing session data
class SessionManager extends ChangeNotifier {
  // Private constructor for singleton pattern
  SessionManager._internal();

  // Singleton instance
  static final SessionManager _instance = SessionManager._internal();

  static const String _prefsKey = 'photobooth.session.current';
  static const Duration kSessionExpiryGrace = Duration(minutes: 5);

  /// Get the singleton instance
  factory SessionManager() => _instance;

  SessionData? _currentSession;
  bool _expiryClearScheduled = false;

  /// Get current session data
  SessionData? get currentSession {
    final s = _currentSession;
    if (s == null) return null;
    final now = DateTime.now();
    if (s.expiresAt.add(kSessionExpiryGrace).isBefore(now)) {
      if (!_expiryClearScheduled) {
        _expiryClearScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _expiryClearScheduled = false;
          _clearSessionInternal(reason: 'expired');
        });
      }
      return null;
    }
    return s;
  }

  /// Get current session ID (convenience method)
  String? get sessionId => currentSession?.id;

  /// Kiosk session auth token for protected API routes (null if no active session).
  String? get kioskAuthToken => currentSession?.kioskAuthToken;

  /// Person count for theme filtering (from preprocess; null until set).
  int? get personCount => currentSession?.personCount;

  PrintOrientation get printOrientation =>
      PrintOrientation.tryParse(currentSession?.printOrientation) ??
      PrintOrientation.fromPersonCount(personCount);

  /// Check if a session exists
  bool get hasSession => currentSession != null;

  /// Check if session is expired (allows [kSessionExpiryGrace] after [expiresAt]).
  bool get isSessionExpired {
    final s = _currentSession;
    if (s == null) return true;
    return s.expiresAt
        .add(kSessionExpiryGrace)
        .isBefore(DateTime.now());
  }

  Future<void> _persistCurrentSession() async {
    final prefs = await SharedPreferences.getInstance();
    final s = _currentSession;
    if (s == null) {
      await prefs.remove(_prefsKey);
      return;
    }
    final map = s.toJson()..remove('userImageUrl');
    await prefs.setString(_prefsKey, jsonEncode(map));
  }

  void _clearSessionInternal({required String reason}) {
    if (_currentSession == null) return;
    _currentSession = null;
    AppLogger.debug('Session cleared ($reason)');
    unawaited(_persistCurrentSession());
    notifyListeners();
  }

  /// Store session data
  void setSession(SessionData session) {
    _currentSession = session;
    AppLogger.debug(
        'Session stored: ${session.id} (expires at: ${session.expiresAt})');
    unawaited(_persistCurrentSession());
    notifyListeners();
  }

  /// Store session data from API response
  void setSessionFromResponse(Map<String, dynamic> response) {
    // PATCH often echoes `userImageUrl` as a huge data URL. Holding and
    // jsonEncoding it for SharedPreferences blows web localStorage quota / RAM
    // and can surface as an uncaught async error right after photo upload.
    // The app already carries pixels in [PhotoModel]; server retains the image.
    final slim = Map<String, dynamic>.from(response)..remove('userImageUrl');
    if (parseKioskAuthToken(slim) == null &&
        _currentSession?.kioskAuthToken != null) {
      slim[kKioskAuthTokenJsonKey] = _currentSession!.kioskAuthToken;
    }
    if (SessionData._personCountFromJson(slim) == null &&
        _currentSession?.personCount != null) {
      slim['personCount'] = _currentSession!.personCount;
    }
    if (SessionData._printOrientationFromJson(slim) == null &&
        _currentSession?.printOrientation != null) {
      slim['printOrientation'] = _currentSession!.printOrientation;
    }
    _currentSession = SessionData.fromJson(slim);
    AppLogger.debug('Session stored from API: ${_currentSession!.id}');
    unawaited(_persistCurrentSession());
    notifyListeners();
  }

  /// Updates authoritative person count after `/api/preprocess-image`.
  void setPersonCount(int count) {
    final s = _currentSession;
    if (s == null || count < 1) return;
    _currentSession = s.copyWith(personCount: count);
    unawaited(_persistCurrentSession());
    notifyListeners();
  }

  void setPrintOrientation(PrintOrientation orientation) {
    final s = _currentSession;
    if (s == null) return;
    _currentSession = s.copyWith(printOrientation: orientation.apiValue);
    unawaited(_persistCurrentSession());
    notifyListeners();
  }

  /// Clear session data
  void clearSession() {
    _clearSessionInternal(reason: 'explicit');
  }

  /// Clears session from memory and **always** removes persisted prefs, even when
  /// [currentSession] was already null (stale disk is wiped).
  ///
  /// For full kiosk customer handoff (session + payment FCM dedup), call
  /// [endPhotoboothCustomerSession] instead.
  ///
  /// Await before navigation or process exit so SharedPreferences can flush on kiosk hardware.
  Future<void> endCustomerSession() async {
    _currentSession = null;
    _expiryClearScheduled = false;
    AppLogger.debug('Session cleared (end customer)');
    await _persistCurrentSession();
    notifyListeners();
  }

  /// Restores persisted session into memory (best-effort).
  ///
  /// On parse/validation failure: discards persisted value and reports error.
  Future<void> restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        await prefs.remove(_prefsKey);
        return;
      }
      final session = SessionData.fromJson(Map<String, dynamic>.from(decoded));
      _currentSession = session;

      // Enforce expiry immediately so first-frame reads never see zombies.
      if (isSessionExpired) {
        _clearSessionInternal(reason: 'expired_restore');
        return;
      }

      AppLogger.debug(
          'Session restored: ${session.id} (expires at: ${session.expiresAt})');
      notifyListeners();
    } catch (e, st) {
      // Corrupt persisted data — discard so we don't loop forever.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_prefsKey);
      } catch (_) {
        // Best-effort
      }
      await ErrorReportingManager.recordError(
        e,
        st,
        reason: 'Session restore failed (corrupt persisted JSON)',
        fatal: false,
      );
    }
  }
}
