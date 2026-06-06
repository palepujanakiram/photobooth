import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/parallel_generation_result.dart';
import 'package:photobooth/services/api_image_url_utils.dart';
import 'package:photobooth/services/api_sse_dispatch.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('dispatchParallelSseBlock handles status start step and complete', () async {
    final slots = ['', ''];
    final quality = <int, double>{};
    final completer = Completer<ParallelGenerationResult>();
    final messages = <String>[];
    final events = <String>[];

    dispatchParallelSseBlock(
      'event: status\ndata: {"imageCount":2}\n',
      slots: slots,
      qualityByIndex: quality,
      completer: completer,
      onProgress: messages.add,
      onSseEvent: (t, _) => events.add(t),
    );
    dispatchParallelSseBlock(
      'event: start\ndata: {"total":2}\n',
      slots: slots,
      qualityByIndex: quality,
      completer: completer,
      onProgress: messages.add,
    );
    dispatchParallelSseBlock(
      'event: step\ndata: {"step":"gen","status":"active"}\n',
      slots: slots,
      qualityByIndex: quality,
      completer: completer,
      onProgress: messages.add,
    );
    dispatchParallelSseBlock(
      'event: image_complete\n'
      'data: {"index":0,"imageUrl":"/api/img/a.jpg","qualityScore":0.8,"completed":1,"total":2}\n',
      slots: slots,
      qualityByIndex: quality,
      completer: completer,
      onProgress: messages.add,
    );
    dispatchParallelSseBlock(
      'event: complete\n'
      'data: {"success":true,"imageUrls":["/api/img/a.jpg"],"runId":"r1","timing":{"totalMs":50}}\n',
      slots: slots,
      qualityByIndex: quality,
      completer: completer,
      onProgress: messages.add,
    );

    final result = await completer.future;
    expect(result.success, isTrue);
    expect(result.runId, 'r1');
    expect(slots.first, contains('/api/img/a.jpg'));
    expect(messages, isNotEmpty);
    expect(events, contains('status'));
  });

  test('dispatchParallelSseBlock image_complete without progress counts', () {
    final slots = [''];
    dispatchParallelSseBlock(
      'event: image_complete\n'
      'data: {"index":0,"imageUrl":"/api/img/a.jpg"}\n',
      slots: slots,
      qualityByIndex: {},
      completer: Completer<ParallelGenerationResult>(),
      onProgress: (m) => expect(m, 'An option finished...'),
    );
  });

  test('dispatchParallelSseBlock handles auxiliary events', () {
    final slots = [''];
    final completer = Completer<ParallelGenerationResult>();
    final messages = <String>[];
    for (final block in [
      'event: attempt_start\ndata: {"attempt":1,"totalAttempts":2}\n',
      'event: attempt_complete\ndata: {"score":0.9}\n',
      'event: commentary\ndata: {"message":"hi"}\n',
      'event: warning\ndata: {"message":"slow"}\n',
      'event: image_failed\ndata: {}\n',
    ]) {
      dispatchParallelSseBlock(
        block,
        slots: slots,
        qualityByIndex: {},
        completer: completer,
        onProgress: messages.add,
      );
    }
    expect(messages, isNotEmpty);
  });

  test('dispatchParallelSseBlock numeric index and timing coercion', () async {
    final slots = ['', ''];
    final completer = Completer<ParallelGenerationResult>();
    dispatchParallelSseBlock(
      'event: image_complete\n'
      'data: {"index":1.0,"imageUrl":"/api/img/b.jpg","qualityScore":0.5}\n',
      slots: slots,
      qualityByIndex: {},
      completer: completer,
    );
    dispatchParallelSseBlock(
      'event: complete\n'
      'data: {"success":true,"imageUrls":["/a","/b"],"timing":{"totalMs":10.0},"selectedIndex":1.0}\n',
      slots: slots,
      qualityByIndex: {},
      completer: completer,
    );
    final result = await completer.future;
    expect(result.selectedIndex, 1);
    expect(result.timingTotalMs, 10);
    expect(slots[1], contains('fly.dev'));
  });

  test('dispatchParallelSseBlock ignores malformed json blocks', () {
    final completer = Completer<ParallelGenerationResult>();
    dispatchParallelSseBlock(
      'event: status\ndata: not-json\n',
      slots: [''],
      qualityByIndex: {},
      completer: completer,
    );
    expect(completer.isCompleted, isFalse);
  });

  test('dispatchParallelSseBlock completes with error event', () async {
    final completer = Completer<ParallelGenerationResult>();
    dispatchParallelSseBlock(
      'event: error\ndata: {"message":"boom"}\n',
      slots: [''],
      qualityByIndex: {},
      completer: completer,
    );
    expect(completer.future, throwsA(isA<ApiException>()));
  });

  test('withGeneratedImageSessionId appends session query', () async {
    SharedPreferences.setMockInitialValues({});
    SessionManager().setSessionFromResponse({
      'id': 'sess-9',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt': DateTime.utc(2026, 12, 1).toIso8601String(),
    });
    final url = withGeneratedImageSessionId(
      'https://example.com/api/img/generated/x.jpg',
    );
    expect(url, contains('sessionId=sess-9'));
  });
}
