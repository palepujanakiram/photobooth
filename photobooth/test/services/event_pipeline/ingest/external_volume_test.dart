import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/services/event_pipeline/ingest/event_storage_channel.dart';

void main() {
  group('fromMap', () {
    test('reads the capacity the picker shows', () {
      final v = ExternalVolume.fromMap(const <Object?, Object?>{
        'uuid': '2609-0353',
        'description': 'SD card',
        'isRemovable': true,
        'isIndexed': true,
        'mediaStoreVolumeName': '2609-0353',
        'totalBytes': 127775277056,
      });
      expect(v.totalBytes, 127775277056);
      expect(v.isUsable, isTrue);
    });

    test('a volume that could not be stat-ed has no size rather than a zero',
        () {
      final v = ExternalVolume.fromMap(const <Object?, Object?>{
        'uuid': 'X',
        'description': 'SD card',
        'isRemovable': true,
        'isIndexed': false,
      });
      expect(v.totalBytes, isNull);
      expect(v.isUsable, isFalse);
    });

    test('a numeric capacity that is not an int is still read', () {
      final v = ExternalVolume.fromMap(const <Object?, Object?>{
        'uuid': 'X',
        'description': 'SD',
        'totalBytes': 1024.0,
      });
      expect(v.totalBytes, 1024);
    });

    test('a non-numeric capacity is ignored', () {
      final v = ExternalVolume.fromMap(const <Object?, Object?>{
        'uuid': 'X',
        'description': 'SD',
        'totalBytes': 'lots',
      });
      expect(v.totalBytes, isNull);
    });
  });

  group('displayLabel', () {
    test('names the card and its id, because two cards share a description',
        () {
      const v = ExternalVolume(
        uuid: '2609-0353',
        description: 'SD card',
        isRemovable: true,
        isIndexed: true,
      );
      expect(v.displayLabel, 'SD card 2609-0353');
    });

    test('falls back to the id alone when there is no description', () {
      const v = ExternalVolume(
        uuid: '2609-0353',
        description: '  ',
        isRemovable: true,
        isIndexed: true,
      );
      expect(v.displayLabel, '2609-0353');
    });

    test('falls back to the description alone when there is no id', () {
      const v = ExternalVolume(
        uuid: '',
        description: 'SD card',
        isRemovable: true,
        isIndexed: true,
      );
      expect(v.displayLabel, 'SD card');
    });

    test('a volume with neither is still nameable', () {
      const v = ExternalVolume(
        uuid: '',
        description: '',
        isRemovable: true,
        isIndexed: true,
      );
      expect(v.displayLabel, 'Card');
    });
  });
}
