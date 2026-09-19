import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/event_pipeline/capture/event_device_capture_uploader.dart';
import 'package:photobooth/utils/exceptions.dart';

void main() {
  EventDeviceCaptureUploader uploader({
    Future<String?> Function()? kioskCode,
    Future<Map<String, dynamic>> Function(String? code)? createSession,
    Future<void> Function(String id, String url)? updateSession,
    void Function(Map<String, dynamic>)? remember,
  }) {
    return EventDeviceCaptureUploader(
      hooks: EventDeviceCaptureUploadHooks(
        kioskCode: kioskCode ?? () async => 'K1',
        createSession: createSession ??
            (code) async => <String, dynamic>{'id': 's1'},
        updateSession: updateSession ?? (id, url) async {},
        rememberSession: remember,
      ),
    );
  }

  test('upload succeeds without a session remember hook', () async {
    final outcome = await uploader().upload(
      Uint8List.fromList(const [1, 2, 3]),
      'a.jpg',
    );
    expect(outcome.queued, isTrue);
  });

  test('empty bytes are not uploaded', () async {
    final outcome = await uploader().upload(Uint8List(0), 'a.jpg');
    expect(outcome.queued, isFalse);
    expect(outcome.message, contains('not where the camera said'));
  });

  test('a still becomes an event-capture session', () async {
    String? seenCode;
    String? seenId;
    String? seenUrl;
    Map<String, dynamic>? remembered;
    final outcome = await uploader(
      kioskCode: () async => 'BOOTH',
      createSession: (code) async {
        seenCode = code;
        return <String, dynamic>{'sessionId': 'sess-9'};
      },
      updateSession: (id, url) async {
        seenId = id;
        seenUrl = url;
      },
      remember: (response) => remembered = response,
    ).upload(Uint8List.fromList(const [1, 2, 3]), 'shot.jpg');

    expect(outcome.queued, isTrue);
    expect(seenCode, 'BOOTH');
    expect(seenId, 'sess-9');
    expect(seenUrl, startsWith('data:image/jpeg;base64,'));
    expect(remembered, containsPair('sessionId', 'sess-9'));
  });

  test('a create response with no session id is reported', () async {
    final outcome = await uploader(
      createSession: (_) async => <String, dynamic>{},
    ).upload(Uint8List.fromList(const [1]), 'a.jpg');
    expect(outcome.queued, isFalse);
    expect(outcome.message, 'Could not store the photo');
  });

  test('API errors surface their message', () async {
    final outcome = await uploader(
      createSession: (_) async => throw ApiException('kiosk missing'),
    ).upload(Uint8List.fromList(const [1]), 'a.jpg');
    expect(outcome.queued, isFalse);
    expect(outcome.message, 'kiosk missing');
  });

  test('unexpected failures stay on the capture screen', () async {
    final outcome = await uploader(
      createSession: (_) async => throw StateError('network'),
    ).upload(Uint8List.fromList(const [1]), 'a.png');
    expect(outcome.queued, isFalse);
    expect(outcome.message, 'Could not queue the photo');
  });

  test('default constructor uses production hooks', () {
    expect(EventDeviceCaptureUploader(), isA<EventDeviceCaptureUploader>());
  });

  test('production hooks can be constructed', () {
    final hooks = EventDeviceCaptureUploader.productionHooks();
    expect(hooks.kioskCode, isA<Future<String?> Function()>());
    expect(hooks.createSession, isNotNull);
    expect(hooks.updateSession, isNotNull);
    expect(hooks.rememberSession, isNotNull);
  });
}
