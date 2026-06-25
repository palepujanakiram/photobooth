import 'package:image/image.dart' as img;

/// Swaps red and blue channels (fixes BGR-as-RGB captures from some UVC stacks).
img.Image swapRedAndBlueChannels(img.Image image) {
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final p = image.getPixel(x, y);
      image.setPixelRgba(x, y, p.b, p.g, p.r, p.a);
    }
  }
  return image;
}
