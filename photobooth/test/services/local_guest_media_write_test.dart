import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/local_guest_media_write.dart';
import 'package:photobooth/services/local_media_store.dart';

void main() {
  late Directory dir;
  late LocalMediaStore store;
  var ids = 0;

  String nextId() => 'id-${ids++}';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('fz_guest_write_');
    store = LocalMediaStore(resolveDirectory: () async => dir);
    ids = 0;
    debugForceSkipGuestMediaWrites = false;
    debugGuestMediaFetchBytes = null;
  });

  tearDown(() async {
    debugForceSkipGuestMediaWrites = false;
    debugGuestMediaFetchBytes = null;
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('allocateGuestMediaRef covers valid, empty, and ext edge cases', () {
    expect(
      allocateGuestMediaRef(prefix: kGuestMediaPrefixGenerated, newId: () => 'abc')
          ?.relativePath,
      'generated/abc.jpg',
    );
    expect(
      allocateGuestMediaRef(
        prefix: kGuestMediaPrefixGenerated,
        ext: '.png',
        newId: () => 'abc',
      )?.relativePath,
      'generated/abc.png',
    );
    expect(
      allocateGuestMediaRef(prefix: kGuestMediaPrefixGenerated, newId: () => '  '),
      isNull,
    );
    expect(
      allocateGuestMediaRef(
        prefix: kGuestMediaPrefixGenerated,
        ext: '.',
        newId: () => 'abc',
      ),
      isNull,
    );
    expect(
      allocateGuestMediaRef(prefix: 'nope', newId: () => 'abc'),
      isNull,
    );
    expect(allocateGuestMediaRef(prefix: kGuestMediaPrefixGenerated), isNotNull);
  });

  test('guestMediaRefFromDiskPath and session URL helpers', () {
    final unix = '${dir.path}/$kFotozenMediaDirName/generated/abc.jpg';
    expect(guestMediaRefFromDiskPath(unix)?.relativePath, 'generated/abc.jpg');
    expect(guestSessionUrlForPath(unix), '/api/img/generated/abc.jpg');
    expect(
      guestMediaRefFromDiskPath(r'C:\booth\fotozen_media\generated\abc.jpg')
          ?.relativePath,
      'generated/abc.jpg',
    );
    expect(
      guestMediaRefFromDiskPath('fotozen_media/generated/abc.jpg')?.relativePath,
      'generated/abc.jpg',
    );
    expect(guestMediaRefFromDiskPath('fotozen_media/generated'), isNull);
    expect(guestMediaRefFromDiskPath('/tmp/other/abc.jpg'), isNull);
    expect(guestSessionUrlForPath('/tmp/other.jpg'), isNull);
    const ref = LocalMediaRef(prefix: 'generated', filename: 'abc.jpg');
    final write = LocalGuestMediaWrite(ref: ref, file: File('/tmp/x'));
    expect(write.apiImgPath, '/api/img/generated/abc.jpg');
    expect(write.localMediaUri, 'local-media://generated/abc.jpg');
    expect(write.sessionUrl, write.apiImgPath);
    expect(guestMediaSessionUrl(ref), write.apiImgPath);
  });

  test('putGuestJpeg writes and rejects empty or skipped IO', () async {
    final written = await putGuestJpeg(
      prefix: kGuestMediaPrefixUserUploads,
      bytes: const [9, 8, 7],
      store: store,
      newId: nextId,
    );
    expect(written, isNotNull);
    expect(written!.ref.relativePath, 'user-uploads/id-0.jpg');
    expect(await written.file.readAsBytes(), [9, 8, 7]);
    expect(await putGuestJpeg(prefix: 'generated', bytes: const [], store: store), isNull);
    debugForceSkipGuestMediaWrites = true;
    expect(
      await putGuestJpeg(prefix: 'generated', bytes: const [1], store: store),
      isNull,
    );
    debugForceSkipGuestMediaWrites = false;
    expect(
      await putGuestJpeg(prefix: 'nope', bytes: const [1], store: store, newId: nextId),
      isNull,
    );
    final failing = LocalMediaStore(
      resolveDirectory: () async => throw StateError('no dir'),
    );
    expect(
      await putGuestJpeg(prefix: 'generated', bytes: const [1], store: failing, newId: nextId),
      isNull,
    );
  });

  test('putGuestJpegFromXFile copies, reuses, and swallows read errors', () async {
    final src = File('${dir.path}/shot.jpg');
    await src.writeAsBytes(const [1, 2, 3]);
    final first = await putGuestJpegFromXFile(
      prefix: kGuestMediaPrefixUserUploads,
      file: XFile(src.path),
      store: store,
      newId: nextId,
    );
    expect(first!.ref.relativePath, 'user-uploads/id-0.jpg');
    final again = await putGuestJpegFromXFile(
      prefix: kGuestMediaPrefixUserUploads,
      file: XFile(first.file.path),
      store: store,
      newId: nextId,
    );
    expect(again!.ref.relativePath, first.ref.relativePath);
    expect(
      await putGuestJpegFromXFile(
        prefix: kGuestMediaPrefixUserUploads,
        file: XFile('${dir.path}/missing-nope.jpg'),
        store: store,
      ),
      isNull,
    );
    debugForceSkipGuestMediaWrites = true;
    expect(
      await putGuestJpegFromXFile(
        prefix: kGuestMediaPrefixUserUploads,
        file: XFile(src.path),
        store: store,
      ),
      isNull,
    );
  });

  test('persistCapturedGuestXFile returns store path or original', () async {
    final src = File('${dir.path}/cap.jpg');
    await src.writeAsBytes(const [4, 5]);
    final original = XFile(src.path);
    final stored = await persistCapturedGuestXFile(
      original,
      store: store,
      newId: nextId,
    );
    expect(stored.path, isNot(original.path));
    expect(stored.path, contains('user-uploads/id-0.jpg'));
    debugForceSkipGuestMediaWrites = true;
    final skipped = await persistCapturedGuestXFile(original, store: store);
    expect(skipped.path, original.path);
  });

  test('persistGuestImageUrl handles data URLs, files, fetch, and skips', () async {
    const payload = [1, 2, 3, 4];
    final dataUrl = 'data:image/jpeg;base64,${base64Encode(payload)}';
    final fromData = await persistGuestImageUrl(
      prefix: kGuestMediaPrefixFotoflashback,
      source: dataUrl,
      store: store,
      newId: nextId,
    );
    expect(fromData, '/api/img/fotoflashback/id-0.jpg');
    expect(
      await persistGuestImageUrl(
        prefix: kGuestMediaPrefixFotoflashback,
        source: 'data:image/jpeg;base64,',
        store: store,
      ),
      'data:image/jpeg;base64,',
    );

    final loose = File('${dir.path}/loose.jpg');
    await loose.writeAsBytes(const [8, 8]);
    final fromFile = await persistGuestImageUrl(
      prefix: kGuestMediaPrefixGenerated,
      source: loose.path,
      store: store,
      newId: nextId,
    );
    expect(fromFile, '/api/img/generated/id-1.jpg');

    expect(
      await persistGuestImageUrl(
        prefix: kGuestMediaPrefixGenerated,
        source: fromFile,
        store: store,
      ),
      fromFile,
    );

    expect(await persistGuestImageUrl(prefix: 'generated', source: '  '), isEmpty);
    debugForceSkipGuestMediaWrites = true;
    expect(
      await persistGuestImageUrl(prefix: 'generated', source: dataUrl, store: store),
      dataUrl,
    );
  });

  test('persistGuestImageUrl fetches missing /api/img and remote URLs', () async {
    const remote = 'https://cdn.example/ai.jpg';
    expect(
      await persistGuestImageUrl(
        prefix: kGuestMediaPrefixGenerated,
        source: remote,
        store: store,
      ),
      remote,
    );
    final saved = await persistGuestImageUrl(
      prefix: kGuestMediaPrefixGenerated,
      source: remote,
      store: store,
      newId: nextId,
      fetchBytes: (_) async => const [11, 12],
    );
    expect(saved, '/api/img/generated/id-0.jpg');

    const proxy = '/api/img/generated/keep-me.jpg';
    final reused = await persistGuestImageUrl(
      prefix: kGuestMediaPrefixGenerated,
      source: proxy,
      store: store,
      fetchBytes: (_) async => const [21],
    );
    expect(reused, proxy);
    expect(
      await File('${dir.path}/generated/keep-me.jpg').readAsBytes(),
      [21],
    );

    expect(
      await persistGuestImageUrl(
        prefix: kGuestMediaPrefixGenerated,
        source: '/api/img/generated/gone.jpg',
        store: store,
        fetchBytes: (_) async => const [],
      ),
      '/api/img/generated/gone.jpg',
    );
    expect(
      await persistGuestImageUrl(
        prefix: kGuestMediaPrefixGenerated,
        source: 'https://x/fail.jpg',
        store: store,
        fetchBytes: (_) async => throw StateError('wan'),
      ),
      'https://x/fail.jpg',
    );

    debugGuestMediaFetchBytes = (_) async => const [33];
    final viaDebug = await persistGuestImageUrl(
      prefix: kGuestMediaPrefixSurpriseMe,
      source: 'https://x/debug.jpg',
      store: store,
      newId: nextId,
    );
    expect(viaDebug, '/api/img/surprise-me/id-1.jpg');
    debugGuestMediaFetchBytes = null;

    final failing = LocalMediaStore(
      resolveDirectory: () async => throw StateError('no dir'),
    );
    expect(
      await persistGuestImageUrl(
        prefix: kGuestMediaPrefixGenerated,
        source: 'https://x/keep.jpg',
        store: failing,
        fetchBytes: (_) async => const [1],
        newId: nextId,
      ),
      'https://x/keep.jpg',
    );
    expect(
      await persistGuestImageUrl(
        prefix: kGuestMediaPrefixGenerated,
        source: dir.path,
        store: store,
      ),
      dir.path,
    );
  });

  test('persistGuestImageUrl keeps source when known-ref write fails', () async {
    await File('${dir.path}/generated').create();
    const proxy = '/api/img/generated/abc.jpg';
    expect(
      await persistGuestImageUrl(
        prefix: kGuestMediaPrefixGenerated,
        source: proxy,
        store: store,
        fetchBytes: (_) async => const [1],
      ),
      proxy,
    );
  });

  test('localXFileForGuestImage prefers store, then disk, then null', () async {
    const ref = LocalMediaRef(prefix: 'generated', filename: 'abc.jpg');
    await store.putBytes(ref, Uint8List.fromList(const [1]));
    final viaUrl = await localXFileForGuestImage(
      '/api/img/generated/abc.jpg',
      store: store,
    );
    expect(viaUrl!.path, endsWith('generated/abc.jpg'));

    final loose = File('${dir.path}/print.jpg');
    await loose.writeAsBytes(const [2]);
    final viaPath = await localXFileForGuestImage(loose.path, store: store);
    expect(viaPath!.path, loose.path);
    final viaFileUrl = await localXFileForGuestImage(
      Uri.file(loose.path).toString(),
      store: store,
    );
    expect(viaFileUrl!.path, loose.path);

    expect(await localXFileForGuestImage(dir.path, store: store), isNull);
    expect(await localXFileForGuestImage('https://x/a.jpg', store: store), isNull);
    expect(await localXFileForGuestImage('data:image/jpeg;base64,AQ==', store: store), isNull);
    expect(await localXFileForGuestImage(' ', store: store), isNull);
    expect(
      await localXFileForGuestImage('${dir.path}/missing.jpg', store: store),
      isNull,
    );
    debugForceSkipGuestMediaWrites = true;
    expect(
      await localXFileForGuestImage('/api/img/generated/abc.jpg', store: store),
      isNull,
    );
  });

  test('guestMediaNetworkFetch uses debug hook then ProtectedImageLoader', () async {
    debugGuestMediaFetchBytes = (_) async => const [7];
    expect(await guestMediaNetworkFetch()('https://x'), [7]);
    debugGuestMediaFetchBytes = null;
    expect(guestMediaNetworkFetch(), isNotNull);
  });

  test('file:// disk path still parses guest media', () {
    final path = '${dir.path}/$kFotozenMediaDirName/previews/z.png';
    expect(
      guestMediaRefFromDiskPath(Uri.file(path).toString())?.relativePath,
      'previews/z.png',
    );
  });
}
