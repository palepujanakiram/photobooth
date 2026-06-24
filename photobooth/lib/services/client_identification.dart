import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:package_info_plus/package_info_plus.dart';

/// Optional HTTP headers for backend analytics (`transformation_runs.metadata.client`).
///
/// Call [ensureInitialized] once during app startup before constructing [ApiService].
class ClientIdentification {
  ClientIdentification._();

  static Map<String, String>? _headers;
  static Future<void>? _initFuture;
  static String? _semverVersion;
  static String? _buildNumber;

  /// Formats [semverVersion] (from `pubspec` / [PackageInfo.version]) for APIs.
  ///
  /// When the app uses **date** versioning:
  /// - `YEAR.MONTH.DAY` → **`yyyy.mm.dd`**
  /// - legacy `YEAR.MONTH.PATCH` where `PATCH = day×10000 + hour×100 + minute` (24h)
  ///   → **`yyyy.mm.dd.hhmm`**
  /// Otherwise returns [semverVersion] unchanged (e.g. legacy `0.1.0`).
  static String formatClientVersionLabel(String semverVersion) {
    final core = semverVersion.split('+').first.trim();
    final parts = core.split('.');
    if (parts.length != 3) return semverVersion;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final patch = int.tryParse(parts[2]);
    if (y == null || m == null || patch == null || y < 2000) return semverVersion;
    if (m < 1 || m > 12) return semverVersion;

    if (patch < 10000) {
      if (patch < 1 || patch > 31) return semverVersion;
      final mm = m.toString().padLeft(2, '0');
      final dd = patch.toString().padLeft(2, '0');
      return '$y.$mm.$dd';
    }

    final day = patch ~/ 10000;
    final hm = patch % 10000;
    final h = hm ~/ 100;
    final min = hm % 100;
    if (day < 1 || day > 31 || h > 23 || min > 59) return semverVersion;
    final mm = m.toString().padLeft(2, '0');
    final dd = day.toString().padLeft(2, '0');
    final hh = h.toString().padLeft(2, '0');
    final nn = min.toString().padLeft(2, '0');
    return '$y.$mm.$dd.$hh$nn';
  }

  /// User-visible line for splash / about: formatted version and store build (`+` suffix).
  static String get versionFooterLabel {
    final raw = _semverVersion;
    if (raw == null || raw.isEmpty) return '';
    final label = formatClientVersionLabel(raw);
    final b = _buildNumber;
    if (b != null && b.isNotEmpty) return '$label · build $b';
    return label;
  }

  /// Short client label: native app builds use `mobile`, Flutter web uses `web`.
  static String get clientType => kIsWeb ? 'web' : 'mobile';

  /// Normalized OS: `web`, `ios`, `android`, etc.
  static String get platformLabel {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }

  /// Populates [httpHeaders] from [PackageInfo]. Safe to await multiple times.
  static Future<void> ensureInitialized() {
    _initFuture ??= _load();
    return _initFuture!;
  }

  static Future<void> _load() async {
    if (_headers != null) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _semverVersion = info.version;
      _buildNumber =
          info.buildNumber.trim().isEmpty ? null : info.buildNumber.trim();
      _headers = {
        'X-Client-Type': clientType,
        'X-Client-Version': formatClientVersionLabel(info.version),
        'X-Client-Platform': platformLabel,
        if (_buildNumber != null) 'X-Client-Build': _buildNumber!,
      };
    } catch (_) {
      _semverVersion = null;
      _buildNumber = null;
      _headers = {
        'X-Client-Type': clientType,
        'X-Client-Version': 'unknown',
        'X-Client-Platform': platformLabel,
      };
    }
  }

  /// Headers to merge into Dio [BaseOptions.headers] / per-request [Options.headers].
  static Map<String, String> get httpHeaders =>
      Map<String, String>.from(_headers ?? const {});

  /// Merges [base] with [httpHeaders] (client keys win on collision).
  static Map<String, dynamic> mergeHeaders(Map<String, dynamic> base) {
    final out = Map<String, dynamic>.from(base);
    out.addAll(httpHeaders);
    return out;
  }
}
