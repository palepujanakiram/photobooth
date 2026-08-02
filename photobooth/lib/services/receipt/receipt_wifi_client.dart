import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// LAN discovery for ESC/POS thermal receipt printers (raw TCP, default :9100).
class ReceiptWifiClient {
  ReceiptWifiClient({
    Future<String?> Function({int parallelism})? discoverFn,
    Future<bool> Function(String host, int port)? probeFn,
  })  : _discoverFn = discoverFn,
        _probeFn = probeFn;

  final Future<String?> Function({int parallelism})? _discoverFn;
  final Future<bool> Function(String host, int port)? _probeFn;

  String? _host;
  int _port = defaultPort;

  String? get host => _host;
  int get port => _port;

  static const defaultPort = 9100;
  static const probeTimeout = Duration(seconds: 2);

  void clear() {
    _host = null;
    _port = defaultPort;
  }

  void configure({required String host, int port = defaultPort}) {
    final trimmed = host.trim();
    _host = trimmed.isEmpty ? null : trimmed;
    _port = port;
  }

  @visibleForTesting
  set hostForTesting(String? value) => _host = value;

  Future<bool> probeHost(String host, {int port = defaultPort}) async {
    if (_probeFn != null) {
      return _probeFn!(host.trim(), port);
    }
    try {
      final socket = await Socket.connect(
        host.trim(),
        port,
        timeout: probeTimeout,
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> discover({int parallelism = 20, int port = defaultPort}) async {
    if (_discoverFn != null) {
      final host = await _discoverFn!(parallelism: parallelism);
      if (host != null) {
        _host = host;
        _port = port;
      }
      return host;
    }

    final localIp = await _localIpv4Address();
    if (localIp == null) return null;
    final prefix = localIp.substring(0, localIp.lastIndexOf('.'));
    return _discoverOnPrefix(prefix, parallelism: parallelism, port: port);
  }

  @visibleForTesting
  Future<String?> discoverOnPrefix(
    String prefix, {
    int parallelism = 20,
    int port = defaultPort,
  }) =>
      _discoverOnPrefix(prefix, parallelism: parallelism, port: port);

  Future<String?> _discoverOnPrefix(
    String prefix, {
    required int parallelism,
    required int port,
  }) async {
    final batchSize = parallelism.clamp(4, 32);

    for (var start = 1; start <= 254; start += batchSize) {
      final end = math.min(start + batchSize - 1, 254);
      final probes = await Future.wait<String?>([
        for (var hostSuffix = start; hostSuffix <= end; hostSuffix++)
          _probeHostCandidate('$prefix.$hostSuffix', port),
      ]);
      for (final host in probes) {
        if (host != null) {
          _host = host;
          _port = port;
          return host;
        }
      }
    }
    return null;
  }

  Future<String?> _probeHostCandidate(String host, int port) async {
    final ok = await probeHost(host, port: port);
    return ok ? host : null;
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
