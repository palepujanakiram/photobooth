/// Reads PNG IHDR width/height without decoding the bitmap.
({int width, int height})? peekPngIhhrDimensions(List<int> bytes) {
  if (bytes.length < 24) return null;
  if (bytes[0] != 0x89 ||
      bytes[1] != 0x50 ||
      bytes[2] != 0x4E ||
      bytes[3] != 0x47) {
    return null;
  }
  final width =
      (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
  final height =
      (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
  if (width <= 0 || height <= 0) return null;
  return (width: width, height: height);
}
