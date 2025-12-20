import 'package:flutter/foundation.dart';

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
    };
  }

  factory SessionData.fromJson(Map<String, dynamic> json) {
    return SessionData(
      id: json['id'] as String,
      termsAccepted: json['termsAccepted'] as bool? ?? false,
      termsAcceptedAt: json['termsAcceptedAt'] != null
          ? DateTime.parse(json['termsAcceptedAt'] as String)
          : DateTime.now(),
      termsAcceptedIp: json['termsAcceptedIp'] as String?,
      termsVersion: json['termsVersion'] as String?,
      attemptsUsed: json['attemptsUsed'] as int? ?? 0,
      generatedImages: json['generatedImages'] as List<dynamic>? ?? [],
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : DateTime.now().add(const Duration(days: 1)),
      kioskId: json['kioskId'] as String?,
      kioskLocation: json['kioskLocation'] as String?,
    );
  }
}

/// Singleton class responsible for managing session data
class SessionManager {
  // Private constructor for singleton pattern
  SessionManager._internal();

  // Singleton instance
  static final SessionManager _instance = SessionManager._internal();

  /// Get the singleton instance
  factory SessionManager() => _instance;

  SessionData? _currentSession;

  /// Get current session data
  SessionData? get currentSession => _currentSession;

  /// Get current session ID (convenience method)
  String? get sessionId => _currentSession?.id;

  /// Check if a session exists
  bool get hasSession => _currentSession != null;

  /// Check if session is expired
  bool get isSessionExpired {
    if (_currentSession == null) return true;
    return DateTime.now().isAfter(_currentSession!.expiresAt);
  }

  /// Store session data
  void setSession(SessionData session) {
    _currentSession = session;
    debugPrint('Session stored: ${session.id} (expires at: ${session.expiresAt})');
  }

  /// Store session data from API response
  void setSessionFromResponse(Map<String, dynamic> response) {
    _currentSession = SessionData.fromJson(response);
    debugPrint('Session stored from API: ${_currentSession!.id}');
  }

  /// Clear session data
  void clearSession() {
    _currentSession = null;
    debugPrint('Session cleared');
  }
}

