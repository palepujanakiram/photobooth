import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth/utils/image_helper_encode.dart';

void main() {
  test('encodeSessionPatchUserImageUrlAsync returns jpeg data url', () async {
    final bytes = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 64, height: 48)),
    );

    final url = await encodeSessionPatchUserImageUrlAsync(bytes);

    expect(url.startsWith('data:image/jpeg;base64,'), isTrue);
    expect(url.length, greaterThan(32));
  });
}
