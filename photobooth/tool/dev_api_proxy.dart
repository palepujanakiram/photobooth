// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Local CORS-friendly proxy for Flutter **web** dev.
///
/// Browser → `http://127.0.0.1:<port>` → `https://fotozenai.fly.dev`
///
/// Usage:
///   dart run tool/dev_api_proxy.dart
///   flutter run -d chrome --dart-define=BASE_URL=http://127.0.0.1:8787
Future<void> main(List<String> args) async {
  var port = 8787;
  var upstream = 'https://fotozenai.fly.dev';
  for (final arg in args) {
    if (arg.startsWith('--port=')) {
      port = int.parse(arg.substring('--port='.length));
    } else if (arg.startsWith('--upstream=')) {
      upstream = arg.substring('--upstream='.length).trim();
    }
  }

  final upstreamUri = Uri.parse(upstream);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  print('Dev API proxy listening on http://127.0.0.1:$port');
  print('Forwarding to $upstream');
  print('');
  print('Run Flutter with:');
  print('  flutter run -d chrome --dart-define=BASE_URL=http://127.0.0.1:$port');

  await for (final request in server) {
    unawaited(_handle(request, upstreamUri));
  }
}

const _allowedHeaders = <String>[
  'content-type',
  'accept',
  'authorization',
  'x-kiosk-session-token',
  'x-staff-token',
  'x-client-type',
  'x-client-version',
  'x-client-platform',
  'x-client-build',
  'x-requested-with',
];

Future<void> _handle(HttpRequest request, Uri upstreamBase) async {
  final origin = request.headers.value('origin');
  try {
    if (request.method == 'OPTIONS') {
      _writeCors(request.response, origin);
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    final target = upstreamBase.replace(
      path: request.uri.path,
      query: request.uri.hasQuery ? request.uri.query : null,
    );

    final body = await request.fold<List<int>>(
      <int>[],
      (previous, data) => previous..addAll(data),
    );

    final forwarded = http.Request(request.method, target);
    request.headers.forEach((name, values) {
      final lower = name.toLowerCase();
      if (lower == 'host' || lower == 'transfer-encoding') return;
      if (!_allowedHeaders.contains(lower) && !lower.startsWith('x-client-')) {
        return;
      }
      forwarded.headers[name] = values.join(', ');
    });

    if (body.isNotEmpty) {
      forwarded.bodyBytes = body;
    }

    final client = http.Client();
    http.StreamedResponse upstream;
    try {
      upstream = await client.send(forwarded);
    } finally {
      client.close();
    }

    final responseBytes = await upstream.stream.toBytes();
    request.response.statusCode = upstream.statusCode;
    _writeCors(request.response, origin);
    upstream.headers.forEach((key, value) {
      final lower = key.toLowerCase();
      if (lower == 'transfer-encoding' || lower == 'access-control-allow-origin') {
        return;
      }
      request.response.headers.set(key, value);
    });
    request.response.add(responseBytes);
    await request.response.close();
  } catch (e, st) {
    print('Proxy error ${request.method} ${request.uri}: $e\n$st');
    try {
      _writeCors(request.response, origin);
      request.response.statusCode = HttpStatus.badGateway;
      request.response.write('Proxy error: $e');
      await request.response.close();
    } on HttpException catch (_) {
      // Response already closed.
    }
  }
}

void _writeCors(HttpResponse response, String? origin) {
  response.headers.set('Access-Control-Allow-Origin', origin ?? '*');
  response.headers.set(
    'Access-Control-Allow-Methods',
    'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  );
  response.headers.set(
    'Access-Control-Allow-Headers',
    _allowedHeaders.join(', '),
  );
  response.headers.set('Access-Control-Allow-Credentials', 'true');
  response.headers.set('Vary', 'Origin');
}
