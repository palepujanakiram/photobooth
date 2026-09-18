import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/classic_deliverable_upload.dart';
import 'package:photobooth/utils/app_strings.dart';

void main() {
  test('persistClassicPrintDeliverable keeps proxy URLs', () async {
    const proxy = '/api/img/fotoflashback/a.jpg';
    final out = await persistClassicPrintDeliverable(
      sessionId: 'sess-1',
      imageUrl: proxy,
      persistLocal: (_) async => 'data:image/jpeg;base64,xx',
      upload: ({required sessionId, required imageDataUrl}) async =>
          '/api/img/fotoflashback/uploaded.jpg',
    );
    expect(out, proxy);
  });

  test('persistClassicPrintDeliverable prefers local persist over upload',
      () async {
    final out = await persistClassicPrintDeliverable(
      sessionId: 'sess-1',
      imageUrl: '${AppStrings.dataImagePrefix}/jpeg;base64,xx',
      persistLocal: (_) async => '/api/img/fotoflashback/disk.jpg',
      upload: ({required sessionId, required imageDataUrl}) async =>
          '/api/img/fotoflashback/uploaded.jpg',
    );
    expect(out, '/api/img/fotoflashback/disk.jpg');
  });

  test('persistClassicPrintDeliverable uploads leftover data URLs', () async {
    var uploaded = false;
    final out = await persistClassicPrintDeliverable(
      sessionId: 'sess-1',
      imageUrl: '${AppStrings.dataImagePrefix}/jpeg;base64,xx',
      persistLocal: (source) async => source,
      upload: ({required sessionId, required imageDataUrl}) async {
        uploaded = sessionId == 'sess-1' && imageDataUrl.contains('base64');
        return '/api/img/fotoflashback/web.jpg';
      },
    );
    expect(uploaded, isTrue);
    expect(out, '/api/img/fotoflashback/web.jpg');
  });

  test('persistClassicPrintDeliverable fail-opens on upload errors', () async {
    const dataUrl = '${AppStrings.dataImagePrefix}/jpeg;base64,xx';
    final failed = await persistClassicPrintDeliverable(
      sessionId: 'sess-1',
      imageUrl: dataUrl,
      persistLocal: (source) async => source,
      upload: ({required sessionId, required imageDataUrl}) async {
        throw StateError('network');
      },
    );
    expect(failed, dataUrl);

    final emptySid = await persistClassicPrintDeliverable(
      sessionId: '  ',
      imageUrl: dataUrl,
      persistLocal: (source) async => source,
      upload: ({required sessionId, required imageDataUrl}) async =>
          '/api/img/fotoflashback/x.jpg',
    );
    expect(emptySid, dataUrl);

    final blank = await persistClassicPrintDeliverable(
      sessionId: 's',
      imageUrl: '   ',
    );
    expect(blank, isEmpty);

    final noUpload = await persistClassicPrintDeliverable(
      sessionId: 's',
      imageUrl: dataUrl,
      persistLocal: (source) async => source,
    );
    expect(noUpload, dataUrl);

    final badUpload = await persistClassicPrintDeliverable(
      sessionId: 's',
      imageUrl: dataUrl,
      persistLocal: (source) async => source,
      upload: ({required sessionId, required imageDataUrl}) async =>
          'https://cdn.example/not-proxy.jpg',
    );
    expect(badUpload, dataUrl);

    expect(await persistClassicPrintLocally('  '), isEmpty);

    final uploaded = await persistClassicPrintDeliverable(
      sessionId: 'sess-1',
      imageUrl: dataUrl,
      upload: ({required sessionId, required imageDataUrl}) async =>
          '/api/img/fotoflashback/direct.jpg',
    );
    expect(uploaded, '/api/img/fotoflashback/direct.jpg');
  });
}
