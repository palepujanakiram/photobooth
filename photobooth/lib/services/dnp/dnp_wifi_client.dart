import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

typedef DnpWifiProgressCallback = void Function(
  String stage,
  String message,
  double? progress,
);

/// WCM Plus HTTP printing with local-subnet discovery (no manual IP).
class DnpWifiClient {
  DnpWifiClient({
    http.Client? client,
    Future<String?> Function({int parallelism})? discoverFn,
  })  : _client = client ?? http.Client(),
        _discoverFn = discoverFn;

  final http.Client _client;
  final Future<String?> Function({int parallelism})? _discoverFn;
  String? _printerBaseUrl;

  String? get printerBaseUrl => _printerBaseUrl;

  void clear() => _printerBaseUrl = null;

  /// Use admin-configured LAN IP (`printerHost`) instead of subnet discovery.
  void configureBaseUrl(String baseUrl) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    _printerBaseUrl = trimmed.isEmpty ? null : trimmed;
  }

  @visibleForTesting
  set printerBaseUrlForTesting(String? url) => configureBaseUrl(url ?? '');

  /// True when [baseUrl] responds like a WCM Plus / DNP HTTP module.
  Future<bool> probeBaseUrl(String baseUrl) => _probeWcm(baseUrl);

  @visibleForTesting
  Future<String?> discoverOnPrefix(String prefix, {int parallelism = 20}) =>
      _discoverOnPrefix(prefix, parallelism: parallelism);

  static const probeTimeout = Duration(seconds: 2);
  static const printTimeout = Duration(seconds: 120);

  Future<String?> discover({int parallelism = 20}) async {
    if (_discoverFn != null) {
      final url = await _discoverFn!(parallelism: parallelism);
      if (url != null) _printerBaseUrl = url;
      return url;
    }
    final localIp = await _localIpv4Address();
    if (localIp == null) return null;
    final prefix = localIp.substring(0, localIp.lastIndexOf('.'));
    return _discoverOnPrefix(prefix, parallelism: parallelism);
  }

  Future<String?> _discoverOnPrefix(String prefix, {int parallelism = 20}) async {
    final batchSize = parallelism.clamp(4, 32);

    for (var start = 1; start <= 254; start += batchSize) {
      final end = math.min(start + batchSize - 1, 254);
      final probes = await Future.wait<String?>([
        for (var host = start; host <= end; host++)
          _probeWcm('http://$prefix.$host').then(
            (ok) => ok ? 'http://$prefix.$host' : null,
          ),
      ]);
      for (final url in probes) {
        if (url != null) {
          _printerBaseUrl = url;
          return url;
        }
      }
    }
    return null;
  }

  Future<void> print({
    required File jpegFile,
    required String printSize,
    required int copies,
    DnpWifiProgressCallback? onProgress,
  }) async {
    final base = _printerBaseUrl;
    if (base == null) {
      throw StateError('No WCM Plus printer found on Wi-Fi');
    }

    for (var index = 0; index < copies; index++) {
      final copyNum = index + 1;
      final baseProgress = index / math.max(copies, 1);
      onProgress?.call(
        'wifi_upload',
        'Sending copy $copyNum of $copies to WCM Plus…',
        baseProgress + 0.5 / math.max(copies, 1),
      );

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$base/api/PrintImage'),
      )
        ..fields['printSize'] = printSize
        ..fields['quantity'] = '1'
        ..fields['imageEdited'] = 'false'
        ..fields['DeviceId'] = 'flutter-photobooth-mobile'
        ..files.add(
          await http.MultipartFile.fromPath('imageFile', jpegFile.path),
        );

      final streamed = await _client.send(request).timeout(printTimeout);
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('WCM print failed: HTTP ${response.statusCode}');
      }

      onProgress?.call(
        'wifi_upload',
        'Copy $copyNum of $copies sent — waiting for printer…',
        (copyNum / math.max(copies, 1)).clamp(0.0, 0.99),
      );
    }
    onProgress?.call('complete', 'Print finished', 1.0);
  }

  Future<bool> _probeWcm(String baseUrl) async {
    try {
      final response = await _client
          .get(Uri.parse('$baseUrl/api/settings'))
          .timeout(probeTimeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _localIpv4Address() async {
    final info = NetworkInfo();
    final wifiIp = await info.getWifiIP();
    if (wifiIp != null && wifiIp.isNotEmpty && wifiIp != '0.0.0.0') {
      return wifiIp;
    }
    return null;
  }
}

/// Binds Android process to Wi-Fi before WCM subnet scan (native no-op elsewhere).
Future<bool> prepareDnpWifiNetwork({bool Function()? isAndroid}) async {
  final onAndroid = isAndroid ?? (() => !kIsWeb && Platform.isAndroid);
  if (!onAndroid()) return true;
  const channel = MethodChannel('com.srisarani.fotozenai/dnp_usb');
  try {
    final bound = await channel.invokeMethod<bool>('prepareWifiNetwork');
    return bound == true;
  } catch (_) {
    return false;
  }
}
