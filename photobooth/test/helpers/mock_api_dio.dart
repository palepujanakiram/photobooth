import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:photobooth/utils/constants.dart';

/// Dio + [DioAdapter] for [ApiService] unit tests (no real network).
({Dio dio, DioAdapter adapter}) createMockApiDio({bool includeAiRoutes = true}) {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConstants.kBaseUrl,
      validateStatus: (_) => true,
    ),
  );
  final adapter = DioAdapter(dio: dio);
  dio.httpClientAdapter = adapter;

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final path = options.uri.path;

        if (options.method == 'PATCH' &&
            path.contains('/api/sessions/') &&
            !path.contains('accept-terms')) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: options.extra['test_patch_body'] as String? ??
                  '{"sessionId":"sess-1","selectedThemeId":"t1"}',
            ),
          );
          return;
        }

        if (options.method == 'POST' &&
            path.endsWith('/accept-terms') &&
            !path.contains('/api/sessions/')) {
          handler.resolve(
            Response(requestOptions: options, statusCode: 200),
          );
          return;
        }

        if (options.method == 'POST' && path.contains('/api/sessions/accept-terms')) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'id': 'sess-new',
                'termsAccepted': true,
                'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
                'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
                'attemptsUsed': 0,
                'generatedImages': <dynamic>[],
              },
            ),
          );
          return;
        }

        if (includeAiRoutes && options.method == 'POST' && path.contains('/api/generate-image')) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'success': true,
                'imageUrl': '/api/img/generated/test.jpg',
                'runId': 'run-1',
                'timing': {'totalMs': 100, 'generationMs': 80},
                'framing': {'personCount': 1},
                'faceVerification': {'match': true},
                'evaluation': {'compositeScore': 0.9},
              },
            ),
          );
          return;
        }

        if (includeAiRoutes &&
            options.method == 'GET' &&
            path.contains('/api/generate-stream-parallel')) {
          const sse = 'event: status\n'
              'data: {"imageCount":2}\n\n'
              'event: image_complete\n'
              'data: {"index":0,"imageUrl":"/api/img/a.jpg","qualityScore":0.9,"completed":1,"total":2}\n\n'
              'event: complete\n'
              'data: {"success":true,"imageUrls":["/api/img/a.jpg"],"runId":"run-sse"}\n\n';
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: ResponseBody.fromString(
                sse,
                200,
                headers: {
                  Headers.contentTypeHeader: ['text/event-stream'],
                },
              ),
            ),
          );
          return;
        }

        if (options.method == 'POST' && path.contains('/api/payment/initiate')) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'id': 'pay-1', 'status': 'PENDING', 'paymentLink': 'https://pay.example'},
            ),
          );
          return;
        }

        if (options.method == 'POST' && path.contains('/api/kiosk/shares')) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'token': 'tok', 'url': 'https://s/tok'},
            ),
          );
          return;
        }

        if (options.method == 'POST' && path.contains('/fcm')) {
          handler.resolve(Response(requestOptions: options, statusCode: 204));
          return;
        }

        if (options.method == 'POST' && path.contains('/receipt')) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'ok': true},
            ),
          );
          return;
        }

        handler.next(options);
      },
    ),
  );

  return (dio: dio, adapter: adapter);
}

/// Second Dio for AI-only client when [ApiService] uses separate [aiDio].
Dio createMockAiDio() => createMockApiDio().dio;
