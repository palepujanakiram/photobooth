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
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return StripOverlayCleanResult(
        images: ['data:image/jpeg;base64,clean$id'],
        cleanedFlags: const [true],
      );
    } finally {
      _inFlight--;
    }
  }
}
