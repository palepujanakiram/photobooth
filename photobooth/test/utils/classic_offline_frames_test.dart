import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/kiosk_frame_model.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/utils/classic_offline_frames.dart';
import 'package:photobooth/utils/strip_filters_catalog_fallback.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stripFiltersCatalogDiskKey sanitizes kiosk codes', () {
    expect(stripFiltersCatalogDiskKey(null), 'strip_filters_default');
    expect(stripFiltersCatalogDiskKey('  '), 'strip_filters_default');
    expect(stripFiltersCatalogDiskKey('dps'), 'strip_filters_DPS');
    expect(stripFiltersCatalogDiskKey('DPS/1'), 'strip_filters_DPS_1');
  });

  test('classicFrameOverlayCacheKey matches AI and 6x2 variants', () {
    expect(classicFrameOverlayCacheKey('ai:frame-1'), 'frame-frame-1');
    expect(
      classicFrameOverlayCacheKey('ai:frame-1', landscape: true),
      'frame-frame-1-land',
    );
    expect(classicFrameOverlayCacheKey('fr:frame-1'), 'frame-frame-1-strip');
    expect(
      classicFrameOverlayCacheKey('f3:frame-1'),
      'frame-frame-1-strip3',
    );
    expect(classicFrameOverlayCacheKey('st:tpl-1'), 'frame-tpl-1');
    expect(classicFrameOverlayCacheKey('classic'), 'frame-classic');
    expect(classicFrameOverlayCacheKey('ai:'), isNull);
    expect(classicFrameOverlayCacheKey(''), isNull);
  });

  test('classicFramesFromKioskFrame emits matching shot-count variants', () {
    const frame = KioskFrameModel(
      id: 'dps-1',
      name: 'Delhi Public School',
      overlayUrl: 'https://cdn.example/ai.png',
      landscapeOverlayUrl: 'https://cdn.example/ai-6x4.png',
      strip: KioskFrameStripAssets(
        overlayUrl: 'https://cdn.example/6x2.png',
        overlay3Url: 'https://cdn.example/6x2-3.png',
        slots: [
          StripTemplateSlot(left: 0.1, top: 0.2, width: 0.8, height: 0.15),
        ],
      ),
    );
    final rows = classicFramesFromKioskFrame(frame);
    expect(rows.map((f) => f.id), ['ai:dps-1', 'fr:dps-1', 'f3:dps-1']);
    expect(rows[0].landscapeOverlayUrl, 'https://cdn.example/ai-6x4.png');
    expect(rows[1].slots.single.top, 0.2);
    expect(classicFramesFromKioskFrame(const KioskFrameModel(
      id: '',
      name: 'X',
      overlayUrl: 'https://cdn.example/ai.png',
    )), isEmpty);
    expect(classicFramesFromKioskFrame(const KioskFrameModel(
      id: 'x',
      name: '  ',
      overlayUrl: 'https://cdn.example/ai.png',
    )), isEmpty);
    expect(
      classicFramesFromKioskFrame(const KioskFrameModel(
        id: 'x',
        name: 'X',
        overlayUrl: '',
      )),
      isEmpty,
    );
  });

  test('mergeOccasionFramesIntoCatalog prepends missing kiosk chrome', () {
    const dps = KioskFrameModel(
      id: 'dps-1',
      name: 'Delhi Public School',
      overlayUrl: 'https://cdn.example/ai.png',
    );
    final fallback = stripFiltersCatalogFallback();
    final merged = mergeOccasionFramesIntoCatalog(fallback, [dps]);
    expect(merged.frames.first.id, 'ai:dps-1');
    expect(merged.frames.where((f) => f.id == 'ai:dps-1'), hasLength(1));
    expect(merged.filters, fallback.filters);

    final again = mergeOccasionFramesIntoCatalog(merged, [dps]);
    expect(again.frames.where((f) => f.id == 'ai:dps-1'), hasLength(1));
    expect(mergeOccasionFramesIntoCatalog(fallback, const []), same(fallback));
  });

  test('readClassicOverlayBytes loads cached PNGs and fails open', () async {
    const occasion = StripFrame(
      id: 'ai:dps-1',
      name: 'DPS',
      description: 'AI',
      kind: 'occasion',
      overlayUrl: 'https://cdn.example/ai.png',
    );
    expect(await readClassicOverlayBytes(occasion), isNull);
    expect(
      await readClassicOverlayBytes(
        const StripFrame(
          id: 'ai:dps-1',
          name: 'DPS',
          description: 'AI',
          kind: 'occasion',
        ),
      ),
      isNull,
    );
    expect(
      await readClassicOverlayBytes(
        const StripFrame(
          id: 'classic',
          name: 'Classic',
          description: 'White',
          overlayUrl: 'https://cdn.example/ai.png',
        ),
      ),
      isNull,
    );
    expect(
      await readClassicOverlayBytes(
        occasion,
        cachedFile: (url, {cacheKey}) async => null,
      ),
      isNull,
    );
    expect(
      await readClassicOverlayBytes(
        occasion,
        cachedFile: (url, {cacheKey}) async => throw StateError('disk'),
      ),
      isNull,
    );

    final temp = await Directory.systemTemp.createTemp('classic-overlay');
    addTearDown(() => temp.delete(recursive: true));
    final empty = File('${temp.path}/empty.png');
    await empty.writeAsBytes(const []);
    expect(
      await readClassicOverlayBytes(
        occasion,
        cachedFile: (url, {cacheKey}) async => empty,
      ),
      isNull,
    );

    final png = File('${temp.path}/ok.png');
    await png.writeAsBytes(const [1, 2, 3]);
    expect(
      await readClassicOverlayBytes(
        occasion,
        cachedFile: (url, {cacheKey}) async {
          expect(url, 'https://cdn.example/ai.png');
          expect(cacheKey, 'frame-dps-1');
          return png;
        },
      ),
      Uint8List.fromList(const [1, 2, 3]),
    );

    const landscapeOccasion = StripFrame(
      id: 'ai:dps-1',
      name: 'DPS',
      description: 'AI',
      kind: 'occasion',
      overlayUrl: 'https://cdn.example/ai-6x4.png',
      landscapeOverlayUrl: 'https://cdn.example/ai-6x4.png',
    );
    expect(
      await readClassicOverlayBytes(
        landscapeOccasion,
        cachedFile: (url, {cacheKey}) async {
          expect(url, 'https://cdn.example/ai-6x4.png');
          expect(cacheKey, 'frame-dps-1-land');
          return png;
        },
      ),
      Uint8List.fromList(const [1, 2, 3]),
    );

    const template = StripFrame(
      id: 'fr:dps-1',
      name: 'DPS 6×2',
      description: 'Strip',
      kind: 'template',
      overlayUrl: 'https://cdn.example/6x2.png',
    );
    expect(
      await readClassicOverlayBytes(
        template,
        cachedFile: (url, {cacheKey}) async {
          expect(cacheKey, 'frame-dps-1-strip');
          return png;
        },
      ),
      isNotEmpty,
    );
  });
}
