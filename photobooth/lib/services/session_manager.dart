import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/logger.dart';
import 'error_reporting/error_reporting_manager.dart';

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
  final String? userImageUrl; // Base64 encoded image from PATCH /api/sessions/{sessionId}
  final String? selectedThemeId; // Theme ID selected by user
  final String? selectedCategoryId; // Category ID of selected theme

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
  });

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
    };
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
    final expiryCutoff = now.add(kSessionExpiryGrace);
    if (s.expiresAt.isBefore(expiryCutoff)) {
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

  /// Check if a session exists
  bool get hasSession => currentSession != null;

  /// Check if session is expired
  bool get isSessionExpired {
    final s = _currentSession;
    if (s == null) return true;
    return s.expiresAt.isBefore(DateTime.now().add(kSessionExpiryGrace));
  }

  Future<void> _persistCurrentSession() async {
    final prefs = await SharedPreferences.getInstance();
    final s = _currentSession;
    if (s == null) {
      await prefs.remove(_prefsKey);
      return;
    }
    await prefs.setString(_prefsKey, jsonEncode(s.toJson()));
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
    _currentSession = SessionData.fromJson(response);
    AppLogger.debug('Session stored from API: ${_currentSession!.id}');
    unawaited(_persistCurrentSession());
    notifyListeners();
  }

  /// Clear session data
  void clearSession() {
    _clearSessionInternal(reason: 'explicit');
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

      AppLogger.debug('Session restored: ${session.id} (expires at: ${session.expiresAt})');
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

