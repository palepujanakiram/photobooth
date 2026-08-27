import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photobooth/services/local_media_store.dart';

void main() {
  test('LocalMediaRef.parse accepts proxy and local-media URLs', () {
    expect(
      LocalMediaRef.parse('/api/img/generated/abc.jpg')?.relativePath,
      'generated/abc.jpg',
    );
    expect(
      LocalMediaRef.parse(
        'https://fotozenai.fly.dev/api/img/previews/x.png',
      )?.relativePath,
      'previews/x.png',
    );
    expect(
      LocalMediaRef.parse('local-media:/generated/abc.jpg')?.relativePath,
      'generated/abc.jpg',
    );
    expect(
      LocalMediaRef.parse('local-media://generated/abc.jpg')?.relativePath,
      'generated/abc.jpg',
    );
    expect(LocalMediaRef.parse(''), isNull);
    expect(LocalMediaRef.parse('/api/img/generated/../x.jpg'), isNull);
    expect(LocalMediaRef.parse('/api/img/unknown/x.jpg'), isNull);
    expect(LocalMediaRef.parse('local-media://onlyone'), isNull);
    expect(LocalMediaRef.parse('/api/img/generated'), isNull);
  });

  test('put and get bytes round-trip', () async {
    final dir = await Directory.systemTemp.createTemp('fz_media_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final store = LocalMediaStore(resolveDirectory: () async => dir);
    const ref = LocalMediaRef(prefix: 'generated', filename: 'abc.jpg');
    final written = await store.putBytes(ref, Uint8List.fromList([9, 8, 7]));
    expect(written, isNotNull);
    final got = await store.getFile(ref);
    expect(await got!.readAsBytes(), [9, 8, 7]);
    final viaUrl = await store.fileForUrl('/api/img/generated/abc.jpg');
    expect(viaUrl!.path, got.path);
    expect(await store.fileForUrl('/api/img/generated/missing.jpg'), isNull);
    expect(await store.fileForUrl('https://example.com/x.jpg'), isNull);
  });

  test('directory failure returns null', () async {
    final store = LocalMediaStore(
      resolveDirectory: () async => throw StateError('no dir'),
    );
    const ref = LocalMediaRef(prefix: 'generated', filename: 'a.jpg');
    expect(await store.putBytes(ref, const [1]), isNull);
    expect(await store.getFile(ref), isNull);
    expect(await store.fileForUrl('/api/img/generated/a.jpg'), isNull);
  });

  test('write failure returns null', () async {
    final dir = await Directory.systemTemp.createTemp('fz_media_ro_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final store = LocalMediaStore(resolveDirectory: () async => dir);
    const ref = LocalMediaRef(prefix: 'generated', filename: 'abc.jpg');
    await File('${dir.path}/generated').create();
    expect(await store.putBytes(ref, const [1, 2, 3]), isNull);
  });

  test('default media directory is created', () async {
    final root = await Directory.systemTemp.createTemp('fz_media_support_');
    addTearDown(() async {
      LocalMediaStore.supportDirectory = getApplicationSupportDirectory;
      if (await root.exists()) await root.delete(recursive: true);
    });
    LocalMediaStore.supportDirectory = () async => root;
    final store = LocalMediaStore();
    const ref = LocalMediaRef(prefix: 'generated', filename: 'abc.jpg');
    final written = await store.putBytes(ref, const [1]);
    expect(written, isNotNull);
    expect(await Directory('${root.path}/fotozen_media').exists(), isTrue);
  });

  test('fromParts, collect refs, list, and delete', () async {
    final dir = await Directory.systemTemp.createTemp('fz_media_list_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final store = LocalMediaStore(resolveDirectory: () async => dir);
    const ref = LocalMediaRef(prefix: 'generated', filename: 'abc.jpg');
    expect(LocalMediaRef.fromParts('generated', 'abc.jpg')?.relativePath, ref.relativePath);
    expect(LocalMediaRef.fromParts('nope', 'abc.jpg'), isNull);
    await store.putBytes(ref, const [1, 2, 3]);
    await Directory('${dir.path}/generated/nested').create();
    await File('${dir.path}/generated/bad name.jpg').writeAsBytes(const [1]);
    final listed = await store.listAll();
    expect(listed.single.ref.relativePath, 'generated/abc.jpg');
    expect(listed.single.bytes, 3);
    expect(
      collectLocalMediaRefs({
        'a': '/api/img/generated/abc.jpg',
        'b': ['/api/img/generated/abc.jpg', 'local-media://previews/x.png'],
      }).map((e) => e.relativePath).toList(),
      ['generated/abc.jpg', 'previews/x.png'],
    );
    expect(collectLocalMediaRefs(3), isEmpty);
    expect(await store.delete(ref), isTrue);
    expect(await store.delete(ref), isFalse);
  });

  test('delete of a directory path returns false', () async {
    final dir = await Directory.systemTemp.createTemp('fz_media_del_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    await Directory('${dir.path}/generated').create();
    await Directory('${dir.path}/generated/abc.jpg').create();
    final store = LocalMediaStore(resolveDirectory: () async => dir);
    const ref = LocalMediaRef(prefix: 'generated', filename: 'abc.jpg');
    expect(await store.delete(ref), isFalse);
  });

  test('delete and list swallow filesystem errors', () async {
    final dir = await Directory.systemTemp.createTemp('fz_media_err_');
    addTearDown(() async {
      await Process.run('chmod', ['u+w', '${dir.path}/generated']);
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final store = LocalMediaStore(resolveDirectory: () async => dir);
    const ref = LocalMediaRef(prefix: 'generated', filename: 'abc.jpg');
    await store.putBytes(ref, const [1]);
    await Process.run('chmod', ['a-w', '${dir.path}/generated']);
    expect(await store.delete(ref), isFalse);
    await Process.run('chmod', ['u+w', '${dir.path}/generated']);
    await Process.run('chmod', ['a-r,a-x', '${dir.path}/generated']);
    expect(await store.listAll(), isEmpty);
    await Process.run('chmod', ['u+rwx', '${dir.path}/generated']);
  });

  test('listAll returns empty when the directory is missing', () async {
    final store = LocalMediaStore(
      resolveDirectory: () async => throw StateError('no dir'),
    );
    expect(await store.listAll(), isEmpty);
  });
}
