/// JSON string scanning helpers for session PATCH responses.
abstract final class ApiJsonScanUtils {
  ApiJsonScanUtils._();

  static bool isJsonWhitespaceCodeUnit(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d;

  static int skipLeadingWhitespace(String raw, int start) {
    var i = start;
    while (i < raw.length && isJsonWhitespaceCodeUnit(raw.codeUnitAt(i))) {
      i++;
    }
    return i;
  }

  static int indexOfLeadingCommaBefore(String raw, int keyIdx) {
    var before = keyIdx - 1;
    while (before >= 0) {
      final c = raw.codeUnitAt(before);
      if (isJsonWhitespaceCodeUnit(c)) {
        before--;
        continue;
      }
      if (raw[before] == ',') return before;
      break;
    }
    return keyIdx;
  }

  static int endIndexAfterJsonValue(String raw, int valueCloseIdx) {
    var removeEnd = valueCloseIdx + 1;
    while (removeEnd < raw.length) {
      final c = raw.codeUnitAt(removeEnd);
      if (isJsonWhitespaceCodeUnit(c)) {
        removeEnd++;
        continue;
      }
      if (c == 0x2c) {
        removeEnd++;
      }
      break;
    }
    return removeEnd;
  }
}
