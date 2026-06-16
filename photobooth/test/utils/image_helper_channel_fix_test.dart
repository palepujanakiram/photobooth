import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photobooth/utils/image_helper_channel_fix.dart';

void main() {
  test('swapRedAndBlueChannels exchanges R and B', () {
    final image = img.Image(width: 1, height: 1);
    image.setPixelRgba(0, 0, 255, 128, 0, 255);
    swapRedAndBlueChannels(image);
    final p = image.getPixel(0, 0);
    expect(p.r, 0);
    expect(p.g, 128);
    expect(p.b, 255);
  });
}
