import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_capture/photo_model.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/utils/route_args.dart';

void main() {
  const theme = ThemeModel(
    id: 't1',
    categoryId: 'c1',
    name: 'Test theme',
    description: 'd',
    promptText: 'p',
  );

  final photo = PhotoModel(
    id: 'p1',
    imageFile: XFile('/tmp/photo_test.jpg'),
    capturedAt: DateTime.utc(2026, 1, 2),
  );

  final generated = GeneratedImage(
    id: 'g1',
    imageUrl: 'https://example.com/out.jpg',
    theme: theme,
  );

  group('GenerateArgs.tryParse', () {
    test('returns same instance when already GenerateArgs', () {
      final args = GenerateArgs(photo: photo, theme: theme);
      expect(GenerateArgs.tryParse(args), same(args));
    });

    test('parses map with photo and theme', () {
      final parsed = GenerateArgs.tryParse({
        'photo': photo,
        'theme': theme,
        'runToken': 42,
      });
      expect(parsed, isNotNull);
      expect(parsed!.photo.id, 'p1');
      expect(parsed.theme.id, 't1');
      expect(parsed.runToken, 42);
    });

    test('runToken can be supplied explicitly', () {
      final a = GenerateArgs(photo: photo, theme: theme, runToken: 1);
      final b = GenerateArgs(photo: photo, theme: theme, runToken: 2);
      expect(a.runToken, 1);
      expect(b.runToken, 2);
    });

    test('returns null when map missing fields', () {
      expect(GenerateArgs.tryParse({'photo': photo}), isNull);
      expect(GenerateArgs.tryParse(<String, Object?>{}), isNull);
    });

    test('returns null when required fields have wrong types', () {
      expect(
        GenerateArgs.tryParse({'photo': 'not-a-photo', 'theme': theme}),
        isNull,
      );
      expect(
        GenerateArgs.tryParse({'photo': photo, 'theme': 42}),
        isNull,
      );
    });
  });

  group('ThemeSelectionArgs.tryParse', () {
    test('parses flags and usedThemeIds from map', () {
      final parsed = ThemeSelectionArgs.tryParse({
        'photo': photo,
        'addOneMoreStyle': true,
        'usedThemeIds': ['a', 'b'],
      });
      expect(parsed, isNotNull);
      expect(parsed!.addOneMoreStyle, isTrue);
      expect(parsed.usedThemeIds, ['a', 'b']);
      expect(parsed.photo!.id, 'p1');
    });

    test('returns null when photo has wrong type', () {
      expect(
        ThemeSelectionArgs.tryParse({'photo': 'oops'}),
        isNull,
      );
    });

    test('tolerates junk entries in usedThemeIds list', () {
      final parsed = ThemeSelectionArgs.tryParse({
        'usedThemeIds': [1, 'z', true],
      });
      expect(parsed, isNotNull);
      expect(parsed!.usedThemeIds, ['1', 'z', 'true']);
    });
  });

  group('ResultArgs.tryParse', () {
    test('parses generated images and optional contact fields', () {
      final parsed = ResultArgs.tryParse({
        'generatedImages': [generated],
        'originalPhoto': photo,
        'customerName': 'Ada',
        'customerPhone': '+1000',
        'customerWhatsappOptIn': true,
      });
      expect(parsed, isNotNull);
      expect(parsed!.generatedImages.length, 1);
      expect(parsed.generatedImages.first.id, 'g1');
      expect(parsed.customerName, 'Ada');
      expect(parsed.customerWhatsappOptIn, isTrue);
    });

    test('returns null when generatedImages empty', () {
      expect(
        ResultArgs.tryParse({
          'generatedImages': <GeneratedImage>[],
        }),
        isNull,
      );
    });

    test('returns null when list has wrong element types', () {
      expect(
        ResultArgs.tryParse({
          'generatedImages': ['not-an-image'],
        }),
        isNull,
      );
    });

    test('returns null when generatedImages is not a list', () {
      expect(
        ResultArgs.tryParse({
          'generatedImages': generated,
        }),
        isNull,
      );
    });

    test('returns null when originalPhoto has wrong type', () {
      expect(
        ResultArgs.tryParse({
          'generatedImages': [generated],
          'originalPhoto': 'nope',
        }),
        isNull,
      );
    });
  });

  group('ThankYouArgs.tryParse', () {
    test('parses string URLs and DateTime', () {
      final expires = DateTime.utc(2026, 6, 1);
      final parsed = ThankYouArgs.tryParse({
        'shareUrl': 'https://short',
        'shareLongUrl': 'https://long',
        'shareExpiresAt': expires,
      });
      expect(parsed, isNotNull);
      expect(parsed!.shareUrl, 'https://short');
      expect(parsed.shareExpiresAt, expires);
    });

    test('parses ISO date string for shareExpiresAt', () {
      final parsed = ThankYouArgs.tryParse({
        'shareExpiresAt': '2026-07-15T12:00:00.000Z',
      });
      expect(parsed, isNotNull);
      expect(parsed!.shareExpiresAt!.year, 2026);
      expect(parsed.shareExpiresAt!.month, 7);
    });
  });

  group('QrShareArgs.tryParse', () {
    test('requires non-empty generatedImages', () {
      final parsed = QrShareArgs.tryParse({
        'generatedImages': [generated],
        'shareUrl': 'https://share',
        'whatsappQueued': true,
        'customerWhatsappOptIn': true,
        'customerPhone': '+91',
      });
      expect(parsed, isNotNull);
      expect(parsed!.generatedImages.first.id, 'g1');
      expect(parsed.whatsappQueued, isTrue);
      expect(parsed.customerPhone, '+91');
    });

    test('returns null when images missing', () {
      expect(QrShareArgs.tryParse(<String, Object?>{}), isNull);
    });

    test('returns null when generatedImages list is malformed', () {
      expect(
        QrShareArgs.tryParse({
          'generatedImages': [42],
        }),
        isNull,
      );
    });
  });
}
