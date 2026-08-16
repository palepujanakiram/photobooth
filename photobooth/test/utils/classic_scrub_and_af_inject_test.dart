import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/app_device_type.dart';
import 'package:photobooth/utils/classic_af_marker_inject.dart';
import 'package:photobooth/utils/classic_strip_scrub_helpers.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ClassicStripScrubGate.resetForTests();
    SessionManager().clearSession();
    SessionManager().setSessionFromResponse({
      'id': 'sess-scrub',
      'sessionId': 'sess-scrub',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.now().toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': <dynamic>[],
      'expiresAt':
          DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    });
  });

  tearDown(() {
    SessionManager().clearSession();
    ClassicStripScrubGate.resetForTests();
  });

  group('classicOverlayScrubEnabled', () {
    test('honors admin enableOsdScrub when build gate is on', () {
      expect(AppConstants.kEnableStripOverlayCleanup, isTrue);
      expect(classicOverlayScrubEnabled(null), isTrue);
      expect(classicOverlayScrubEnabled(true), isTrue);
      expect(classicOverlayScrubEnabled(false), isFalse);
    });
  });

  group('classicComposeRequestsOverlayCleanup', () {
    test('compose never requests a second Gemini scrub pass', () {
      expect(classicComposeRequestsOverlayCleanup(), isFalse);
    });
  });

  group('classicOverlayScrubDuringCaptureEnabled', () {
    test('stays OFF on capture for all devices (look screen scrubs)', () {
      expect(
        classicOverlayScrubDuringCaptureEnabled(
          enableOsdScrub: true,
          deviceType: AppDeviceType.androidTv,
        ),
        isFalse,
      );
      expect(
        classicOverlayScrubDuringCaptureEnabled(
          enableOsdScrub: true,
          deviceType: AppDeviceType.androidPhone,
        ),
        isFalse,
      );
      expect(
        classicOverlayScrubDuringCaptureEnabled(
          enableOsdScrub: false,
          deviceType: AppDeviceType.androidPhone,
        ),
        isFalse,
      );
    });
  });

  group('scrubClassicShotDataUrl', () {
    test('returns raw encode when scrub disabled', () async {
      final out = await scrubClassicShotDataUrl(
        encodeShotDataUrl: () async => 'data:image/jpeg;base64,raw',
        enableScrub: false,
      );
      expect(out.dataUrl, 'data:image/jpeg;base64,raw');
      expect(out.scrubbed, isFalse);
    });

    test('skips Gemini when cancelled while waiting on scrub gate', () async {
      final gateHold = Completer<void>();
      final first = ClassicStripScrubGate.enqueue(() async {
        await gateHold.future;
        return 0;
      });

      var cancelled = false;
      final scrubFuture = scrubClassicShotDataUrl(
        encodeShotDataUrl: () async => 'data:image/jpeg;base64,raw',
        enableScrub: true,
        apiService: _RecordingScrubApi(),
        isCancelled: () => cancelled,
      );

      // Past the pre-gate cancel check; waiting behind [first].
      await Future<void>.delayed(Duration.zero);
      cancelled = true;
      gateHold.complete();
      await first;

      final out = await scrubFuture;
      expect(out.scrubbed, isFalse);
      expect(out.dataUrl, 'data:image/jpeg;base64,raw');
    });

    test('serializes concurrent scrub API calls', () async {
      final api = _RecordingScrubApi();

      Future<ClassicShotScrubResult> kick(int id) {
        return scrubClassicShotDataUrl(
          encodeShotDataUrl: () async => 'data:image/jpeg;base64,shot$id',
          enableScrub: true,
          apiService: api,
        );
      }

      final results = await Future.wait([kick(1), kick(2), kick(3)]);

      expect(api.maxInFlight, 1);
      expect(api.started.toSet(), {1, 2, 3});
      expect(api.finished.toSet(), {1, 2, 3});
      expect(results.map((r) => r.scrubbed), everyElement(isTrue));
    });

    test('scrubbed is false when server cleanedFlags are false', () async {
      final api = _RecordingScrubApi()..forceCleaned = false;
      final out = await scrubClassicShotDataUrl(
        encodeShotDataUrl: () async => 'data:image/jpeg;base64,shot9',
        enableScrub: true,
        apiService: api,
      );
      expect(out.scrubbed, isFalse);
      expect(out.dataUrl, 'data:image/jpeg;base64,shot9_echo');
    });

    test('returns raw when session id missing', () async {
      SessionManager().clearSession();
      final out = await scrubClassicShotDataUrl(
        encodeShotDataUrl: () async => 'data:image/jpeg;base64,raw',
        enableScrub: true,
      );
      expect(out.scrubbed, isFalse);
      expect(out.dataUrl, 'data:image/jpeg;base64,raw');
    });

    test('fail-open when scrub API throws', () async {
      final api = _ThrowingScrubApi();
      final out = await scrubClassicShotDataUrl(
        encodeShotDataUrl: () async => 'data:image/jpeg;base64,shot',
        enableScrub: true,
        apiService: api,
      );
      expect(out.scrubbed, isFalse);
      expect(out.dataUrl, 'data:image/jpeg;base64,shot');
    });

    test('enqueue propagates scrub failures without breaking queue', () async {
      final api = _ThrowingScrubApi();
      await expectLater(
        scrubClassicShotDataUrl(
          encodeShotDataUrl: () async => 'data:image/jpeg;base64,a',
          enableScrub: true,
          apiService: api,
        ),
        completion(isA<ClassicShotScrubResult>()),
      );
      final second = await scrubClassicShotDataUrl(
        encodeShotDataUrl: () async => 'data:image/jpeg;base64,b',
        enableScrub: true,
        apiService: api,
      );
      expect(second.dataUrl, contains('b'));
    });

    test('enqueue error in scrub fn still completes future', () async {
      await expectLater(
        ClassicStripScrubGate.enqueue(() async {
          throw StateError('queue boom');
        }),
        throwsStateError,
      );
      final ok = await ClassicStripScrubGate.enqueue(() async => 1);
      expect(ok, 1);
    });
  });

  group('injectClassicAfMarkers', () {
    test('burns white AF brackets into a still', () async {
      final canvas = img.Image(width: 200, height: 280);
      img.fill(canvas, color: img.ColorRgb8(40, 40, 40));
      final bytes = Uint8List.fromList(img.encodeJpg(canvas, quality: 90));
      final source = XFile.fromData(
        bytes,
        mimeType: 'image/jpeg',
        name: 'plain.jpg',
      );

      final out = await injectClassicAfMarkers(source);
      final outBytes = await out.readAsBytes();
      final decoded = img.decodeImage(outBytes);
      expect(decoded, isNotNull);

      var bright = 0;
      for (final p in decoded!) {
        if (p.r > 200 && p.g > 200 && p.b > 200) bright++;
      }
      expect(bright, greaterThan(80));
    });

    test('returns source unchanged when bytes are not an image', () async {
      final source = XFile.fromData(
        Uint8List.fromList([1, 2, 3, 4]),
        mimeType: 'image/jpeg',
        name: 'bad.jpg',
      );
      final out = await injectClassicAfMarkers(source);
      expect(await out.readAsBytes(), await source.readAsBytes());
    });
  });
}

class _ThrowingScrubApi extends FakeApiService {
  @override
  Future<StripOverlayCleanResult> cleanStripOverlays({
    required String sessionId,
    required List<String> images,
  }) async {
    throw Exception('scrub failed');
  }
}

class _RecordingScrubApi extends FakeApiService {
  int _inFlight = 0;
  int maxInFlight = 0;
  final List<int> started = [];
  final List<int> finished = [];
  bool forceCleaned = true;

  @override
  Future<StripOverlayCleanResult> cleanStripOverlays({
    required String sessionId,
    required List<String> images,
  }) async {
    final id = int.parse(images.first.split('shot').last);
    started.add(id);
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      finished.add(id);
      if (!forceCleaned) {
        return StripOverlayCleanResult(
          images: ['${images.first}_echo'],
          cleanedFlags: const [false],
        );
      }
      return StripOverlayCleanResult(
        images: ['data:image/jpeg;base64,clean$id'],
        cleanedFlags: const [true],
      );
    } finally {
      _inFlight--;
    }
  }
}
