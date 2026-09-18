import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/event_pipeline/ingest/ingest_source.dart';
import 'package:photobooth/services/event_pipeline/ingest/ingest_thumbnailer.dart';

IngestCandidate candidate(String name, {int size = 1000}) {
  return IngestCandidate(
    sourceId: 'VOL',
    relativePath: 'DCIM/100CANON/$name',
    displayName: name,
    sizeBytes: size,
    modifiedAtMs: 10,
    uri: 'content://media/$name',
  );
}

/// Records calls and lets each one be completed by hand, so concurrency is
/// observable rather than a race.
class FakeChannel {
  FakeChannel(this.name);

  final String name;
  final List<Map<Object?, Object?>> calls = [];
  final List<Completer<Uint8List?>> pending = [];
  bool throwOnCall = false;

  MethodChannel get channel {
    final ch = MethodChannel(name);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (call) async {
      calls.add(Map<Object?, Object?>.from(call.arguments as Map));
      if (throwOnCall) {
        throw PlatformException(code: 'boom', message: 'no decoder');
      }
      final completer = Completer<Uint8List?>();
      pending.add(completer);
      return completer.future;
    });
    return ch;
  }

  void completeAll(Uint8List? bytes) {
    for (final c in pending) {
      if (!c.isCompleted) c.complete(bytes);
    }
    pending.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeChannel fake;
  var n = 0;

  setUp(() {
    fake = FakeChannel('test_thumbs_${n++}');
  });

  final jpeg = Uint8List.fromList([1, 2, 3, 4]);

  test('decodes a candidate and caches the bytes', () async {
    final thumbs = IngestThumbnailer(channel: fake.channel);
    addTearDown(thumbs.dispose);

    final future = thumbs.thumbnail(candidate('a.jpg'));
    await Future<void>.delayed(Duration.zero);
    fake.completeAll(jpeg);

    expect(await future, jpeg);
    expect(thumbs.cached(candidate('a.jpg')), jpeg);
    expect(fake.calls.single['uri'], 'content://media/a.jpg');
    expect(fake.calls.single['shortSide'], 256);
  });

  test('a second ask for a cached image does not decode again', () async {
    final thumbs = IngestThumbnailer(channel: fake.channel);
    addTearDown(thumbs.dispose);

    final first = thumbs.thumbnail(candidate('a.jpg'));
    await Future<void>.delayed(Duration.zero);
    fake.completeAll(jpeg);
    await first;

    await thumbs.thumbnail(candidate('a.jpg'));
    expect(fake.calls, hasLength(1),
        reason: 'scrolling back must not re-decode the card');
  });

  test('two tiles asking for the same image share one decode', () async {
    final thumbs = IngestThumbnailer(channel: fake.channel);
    addTearDown(thumbs.dispose);

    final a = thumbs.thumbnail(candidate('a.jpg'));
    final b = thumbs.thumbnail(candidate('a.jpg'));
    await Future<void>.delayed(Duration.zero);
    expect(fake.calls, hasLength(1));

    fake.completeAll(jpeg);
    expect(await a, jpeg);
    expect(await b, jpeg);
  });

  test('never runs more than maxConcurrent decodes at once', () async {
    final thumbs = IngestThumbnailer(channel: fake.channel, maxConcurrent: 2);
    addTearDown(thumbs.dispose);

    // A fling asks for far more tiles than the device should decode at once.
    final futures = [
      for (var i = 0; i < 8; i++) thumbs.thumbnail(candidate('p$i.jpg')),
    ];
    await Future<void>.delayed(Duration.zero);

    expect(fake.calls, hasLength(2),
        reason: 'an unbounded fan-out starves the rest of the device');

    fake.completeAll(jpeg);
    await Future<void>.delayed(Duration.zero);
    expect(fake.calls.length, greaterThan(2));

    fake.completeAll(jpeg);
    await Future<void>.delayed(Duration.zero);
    fake.completeAll(jpeg);
    await Future<void>.delayed(Duration.zero);
    fake.completeAll(jpeg);
    await Future.wait(futures);
    expect(fake.calls, hasLength(8));
  });

  test('a decode failure is a null tile, not a thrown error', () async {
    fake.throwOnCall = true;
    final thumbs = IngestThumbnailer(channel: fake.channel);
    addTearDown(thumbs.dispose);

    // A card of mixed junk is normal; the picker must survive it.
    expect(await thumbs.thumbnail(candidate('bad.jpg')), isNull);
  });

  test('a failure is remembered so it is not retried on every scroll',
      () async {
    fake.throwOnCall = true;
    final thumbs = IngestThumbnailer(channel: fake.channel);
    addTearDown(thumbs.dispose);

    await thumbs.thumbnail(candidate('bad.jpg'));
    await thumbs.thumbnail(candidate('bad.jpg'));

    expect(fake.calls, hasLength(1));
    expect(thumbs.isCached(candidate('bad.jpg')), isTrue);
    expect(thumbs.cached(candidate('bad.jpg')), isNull);
  });

  test('empty bytes read as no thumbnail rather than a broken image', () async {
    final thumbs = IngestThumbnailer(channel: fake.channel);
    addTearDown(thumbs.dispose);

    final future = thumbs.thumbnail(candidate('a.jpg'));
    await Future<void>.delayed(Duration.zero);
    fake.completeAll(Uint8List(0));

    expect(await future, isNull);
  });

  test('the cache evicts the oldest rather than growing without bound',
      () async {
    final thumbs = IngestThumbnailer(channel: fake.channel, maxCached: 2);
    addTearDown(thumbs.dispose);

    for (final name in ['a.jpg', 'b.jpg', 'c.jpg']) {
      final f = thumbs.thumbnail(candidate(name));
      await Future<void>.delayed(Duration.zero);
      fake.completeAll(jpeg);
      await f;
    }

    // A night's scrolling through thousands of frames must not end in an OOM.
    expect(thumbs.isCached(candidate('a.jpg')), isFalse);
    expect(thumbs.isCached(candidate('b.jpg')), isTrue);
    expect(thumbs.isCached(candidate('c.jpg')), isTrue);
  });

  test('re-caching a hit moves it back to the newest slot', () async {
    final thumbs = IngestThumbnailer(channel: fake.channel, maxCached: 2);
    addTearDown(thumbs.dispose);

    for (final name in ['a.jpg', 'b.jpg']) {
      final f = thumbs.thumbnail(candidate(name));
      await Future<void>.delayed(Duration.zero);
      fake.completeAll(jpeg);
      await f;
    }
    // Re-reading 'a' should not save it: a cache hit does not re-enter the map,
    // so eviction order stays insertion order.
    await thumbs.thumbnail(candidate('a.jpg'));
    final f = thumbs.thumbnail(candidate('c.jpg'));
    await Future<void>.delayed(Duration.zero);
    fake.completeAll(jpeg);
    await f;

    expect(thumbs.isCached(candidate('c.jpg')), isTrue);
  });

  test('the dedupe key includes size, so a reformatted card re-decodes',
      () async {
    final thumbs = IngestThumbnailer(channel: fake.channel);
    addTearDown(thumbs.dispose);

    final first = thumbs.thumbnail(candidate('IMG_0001.JPG', size: 100));
    await Future<void>.delayed(Duration.zero);
    fake.completeAll(jpeg);
    await first;

    // Same filename after a reformat and renumber, different photograph.
    final second = thumbs.thumbnail(candidate('IMG_0001.JPG', size: 200));
    await Future<void>.delayed(Duration.zero);
    fake.completeAll(jpeg);
    await second;

    expect(fake.calls, hasLength(2));
  });

  test('clear drops what is held', () async {
    final thumbs = IngestThumbnailer(channel: fake.channel);
    addTearDown(thumbs.dispose);

    final f = thumbs.thumbnail(candidate('a.jpg'));
    await Future<void>.delayed(Duration.zero);
    fake.completeAll(jpeg);
    await f;
    expect(thumbs.isCached(candidate('a.jpg')), isTrue);

    thumbs.clear();
    expect(thumbs.isCached(candidate('a.jpg')), isFalse);
  });

  test('dispose completes anything still queued instead of hanging a tile',
      () async {
    final thumbs = IngestThumbnailer(channel: fake.channel, maxConcurrent: 1);

    final running = thumbs.thumbnail(candidate('a.jpg'));
    final queued = thumbs.thumbnail(candidate('b.jpg'));
    await Future<void>.delayed(Duration.zero);

    thumbs.dispose();
    expect(await queued, isNull);

    fake.completeAll(jpeg);
    await running;
  });

  test('a decode landing after dispose is not cached', () async {
    final thumbs = IngestThumbnailer(channel: fake.channel);

    final running = thumbs.thumbnail(candidate('a.jpg'));
    await Future<void>.delayed(Duration.zero);
    thumbs.dispose();
    fake.completeAll(jpeg);
    await running;

    expect(thumbs.isCached(candidate('a.jpg')), isFalse);
  });
}
