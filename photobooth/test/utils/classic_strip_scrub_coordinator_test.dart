import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/classic_strip_scrub_coordinator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ClassicStripScrubCoordinator.instance.resetForTests();
    SessionManager().clearSession();
    SessionManager().setSessionFromResponse({
      'id': 'sess-coord',
      'sessionId': 'sess-coord',
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
    ClassicStripScrubCoordinator.instance.resetForTests();
  });

  test('enqueueShot updates dots and survives awaitAll order', () async {
    final api = _SlowScrubApi();
    final coord = ClassicStripScrubCoordinator.instance;

    final f1 = coord.enqueueShot(
      encodeShotDataUrl: () async => 'data:image/jpeg;base64,shot1',
      enableScrub: true,
      apiService: api,
    );
    expect(coord.statuses, [ClassicScrubDotStatus.scrubbing]);

    final f2 = coord.enqueueShot(
      encodeShotDataUrl: () async => 'data:image/jpeg;base64,shot2',
      enableScrub: true,
      apiService: api,
    );
    expect(coord.shotCount, 2);

    final results = await Future.wait([f1, f2]);
    expect(results.map((r) => r.scrubbed), everyElement(isTrue));
    expect(
      coord.statuses,
      everyElement(ClassicScrubDotStatus.cleaned),
    );

    final awaited = await coord.awaitAll();
    expect(awaited.map((r) => r.dataUrl), [
      'data:image/jpeg;base64,clean1',
      'data:image/jpeg;base64,clean2',
    ]);
    expect(api.maxInFlight, 1);
  });

  test('awaitEncodedReady returns before slow Gemini scrub finishes', () async {
    final api = _SlowScrubApi(delay: const Duration(seconds: 2));
    final coord = ClassicStripScrubCoordinator.instance;
    final encodeGate = Completer<void>();

    unawaited(
      coord.enqueueShot(
        encodeShotDataUrl: () async {
          await encodeGate.future;
          return 'data:image/jpeg;base64,shot1';
        },
        enableScrub: true,
        apiService: api,
      ),
    );
    unawaited(
      coord.enqueueShot(
        encodeShotDataUrl: () async {
          await encodeGate.future;
          return 'data:image/jpeg;base64,shot2';
        },
        enableScrub: true,
        apiService: api,
      ),
    );

    encodeGate.complete();
    final encoded = await coord.awaitEncodedReady().timeout(
      const Duration(milliseconds: 500),
    );
    expect(encoded, hasLength(2));
    expect(encoded.map((r) => r.dataUrl), [
      'data:image/jpeg;base64,shot1',
      'data:image/jpeg;base64,shot2',
    ]);
    expect(encoded.map((r) => r.scrubbed), everyElement(isFalse));
    expect(coord.hasShot(0), isTrue);
    expect(coord.hasShot(2), isFalse);

    final scrubbed = await Future.wait([
      coord.awaitShot(0),
      coord.awaitShot(1),
    ]);
    expect(scrubbed.map((r) => r.scrubbed), everyElement(isTrue));
    expect(scrubbed.map((r) => r.dataUrl), [
      'data:image/jpeg;base64,clean1',
      'data:image/jpeg;base64,clean2',
    ]);
  });

  test('awaitEncodedReady prefers finished scrub when already done', () async {
    final api = _SlowScrubApi(delay: Duration.zero);
    final coord = ClassicStripScrubCoordinator.instance;
    await coord.enqueueShot(
      encodeShotDataUrl: () async => 'data:image/jpeg;base64,shot1',
      enableScrub: true,
      apiService: api,
    );
    final encoded = await coord.awaitEncodedReady();
    expect(encoded, hasLength(1));
    expect(encoded.single.scrubbed, isTrue);
    expect(encoded.single.dataUrl, 'data:image/jpeg;base64,clean1');
  });

  test('awaitShot errors for out-of-range index', () async {
    final coord = ClassicStripScrubCoordinator.instance;
    await expectLater(coord.awaitShot(0), throwsRangeError);
  });

  test('enqueueShot fail-open when encode throws', () async {
    final coord = ClassicStripScrubCoordinator.instance;
    final result = await coord.enqueueShot(
      encodeShotDataUrl: () async => throw Exception('encode boom'),
      enableScrub: true,
      apiService: _SlowScrubApi(),
    );
    expect(result.scrubbed, isFalse);
    expect(result.dataUrl, isEmpty);
    expect(coord.statuses, [ClassicScrubDotStatus.failed]);

    final encoded = await coord.awaitEncodedReady();
    expect(encoded.single.dataUrl, isEmpty);
    expect(encoded.single.scrubbed, isFalse);
  });

  test('dropLast removes progress slot', () async {
    final coord = ClassicStripScrubCoordinator.instance;
    final f = coord.enqueueShot(
      encodeShotDataUrl: () async => 'data:image/jpeg;base64,shot1',
      enableScrub: false,
    );
    await f;
    expect(coord.shotCount, 1);
    expect(coord.statuses, [ClassicScrubDotStatus.cleaned]);
    coord.dropLast();
    expect(coord.shotCount, 0);
  });
}

class _SlowScrubApi extends FakeApiService {
  _SlowScrubApi({this.delay = const Duration(milliseconds: 20)});

  final Duration delay;
  int _inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<StripOverlayCleanResult> cleanStripOverlays({
    required String sessionId,
    required List<String> images,
  }) async {
    final id = images.first.contains('shot1') ? 1 : 2;
    _inFlight++;
    if (_inFlight > maxInFlight) maxInFlight = _inFlight;
    try {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
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
