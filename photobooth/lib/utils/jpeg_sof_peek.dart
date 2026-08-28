/// Reads JPEG SOF width/height without decoding the bitmap.
({int width, int height})? peekJpegSofDimensions(List<int> bytes) {
  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return null;
  }
  var i = 2;
  while (i + 1 < bytes.length) {
    if (bytes[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = bytes[i + 1];
    if (marker == 0xD8 ||
        marker == 0xD9 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    if (i + 3 >= bytes.length) return null;
    final len = (bytes[i + 2] << 8) | bytes[i + 3];
    if (len < 2) return null;
    final isSof = marker == 0xC0 ||
        marker == 0xC1 ||
        marker == 0xC2 ||
        marker == 0xC3;
    if (isSof) {
      if (i + 8 >= bytes.length) return null;
      final height = (bytes[i + 5] << 8) | bytes[i + 6];
      final width = (bytes[i + 7] << 8) | bytes[i + 8];
      if (width > 0 && height > 0) {
        return (width: width, height: height);
      }
      return null;
    }
    i += 2 + len;
  }
  return null;
}
