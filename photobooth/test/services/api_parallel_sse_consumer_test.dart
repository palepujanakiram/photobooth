import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/api_parallel_sse_consumer.dart';
import 'package:photobooth/utils/exceptions.dart';

void main() {
  test('consumeParallelGenerationSseStream completes on complete event', () async {
    const sse = 'event: complete\n'
        'data: {"success":true,"imageUrls":["/api/img/a.jpg"]}\n\n';
    final body = ResponseBody.fromString(sse, 200);
    final result = await consumeParallelGenerationSseStream(
      body,
      slotCount: 1,
      onProgress: (_) {},
    );
    expect(result.success, isTrue);
    expect(result.imageUrlsBySlot.first, contains('/api/img/a.jpg'));
  });

  test('consumeParallelGenerationSseStream handles split chunks and CRLF', () async {
    final stream = Stream<Uint8List>.fromIterable([
      Uint8List.fromList(utf8.encode('event: image_complete\r\n')),
      Uint8List.fromList(
        utf8.encode('data: {"index":0,"imageUrl":"/api/img/x.jpg"}\n\n'),
      ),
    ]);
    final body = ResponseBody(stream, 200);
    final result = await consumeParallelGenerationSseStream(body, slotCount: 1);
    expect(result.imageUrlsBySlot.first, contains('/api/img/x.jpg'));
  });

  test('consumeParallelGenerationSseStream fails on error event', () async {
    const sse = 'event: error\n'
        'data: {"message":"boom"}\n\n';
    final body = ResponseBody.fromString(sse, 200);
    await expectLater(
      consumeParallelGenerationSseStream(body, slotCount: 1),
      throwsA(isA<ApiException>()),
    );
  });

  test('consumeParallelGenerationSseStream fails when stream has no images', () async {
    const sse = 'event: status\n'
        'data: {"imageCount":1}\n\n';
    final body = ResponseBody.fromString(sse, 200);
    await expectLater(
      consumeParallelGenerationSseStream(body, slotCount: 1),
      throwsA(
        predicate<ApiException>((e) => e.message.contains('without any image')),
      ),
    );
  });

  test('consumeParallelGenerationSseStream maps stream errors', () async {
    final body = ResponseBody(
      Stream<Uint8List>.error(Exception('broken pipe')),
      200,
    );
    await expectLater(
      consumeParallelGenerationSseStream(body, slotCount: 1),
      throwsA(
        predicate<ApiException>((e) => e.message.contains('stream failed')),
      ),
    );
  });

  test('consumeParallelGenerationSseStream dispatches trailing buffer without final blank line', () async {
    const sse = 'event: image_complete\n'
        'data: {"index":0,"imageUrl":"/api/img/trailing.jpg"}';
    final body = ResponseBody.fromString(sse, 200);
    final result = await consumeParallelGenerationSseStream(body, slotCount: 1);
    expect(result.imageUrlsBySlot.first, contains('trailing.jpg'));
  });

  test('consumeParallelGenerationSseStream strips CR before block separator', () async {
    const sse = 'event: image_complete\r\n'
        'data: {"index":0,"imageUrl":"/api/img/cr.jpg"}\r\n\n';
    final body = ResponseBody.fromString(sse, 200);
    final result = await consumeParallelGenerationSseStream(body, slotCount: 1);
    expect(result.imageUrlsBySlot.first, contains('/api/img/cr.jpg'));
  });

  test('consumeParallelGenerationSseStream completes partial slots at end', () async {
    const sse = 'event: image_complete\n'
        'data: {"index":0,"imageUrl":"/api/img/partial.jpg"}\n\n';
    final body = ResponseBody.fromString(sse, 200);
    final result = await consumeParallelGenerationSseStream(body, slotCount: 2);
    expect(result.success, isTrue);
    expect(result.imageUrlsBySlot.first, contains('partial.jpg'));
  });

  test('consumeParallelGenerationSseStream times out on stalled stream', () async {
    final controller = StreamController<Uint8List>();
    addTearDown(controller.close);
    final body = ResponseBody(controller.stream, 200);
    await expectLater(
      consumeParallelGenerationSseStream(
        body,
        slotCount: 1,
        timeout: const Duration(milliseconds: 50),
      ),
      throwsA(
        predicate<ApiException>((e) => e.message.contains('timed out')),
      ),
    );
  });
}
