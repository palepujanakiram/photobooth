import '../models/event_info_model.dart';

const int kEventSkinFallbackFrom = 0xE3A65C;
const int kEventSkinFallbackTo = 0x6E5391;
const int kEventSkinFallbackInk = 0xFFFFFF;
const int kEventLookSelectedBorder = 0xFF1B365D;

int eventChromeArgb(String hex, int fallbackRgb) {
  return 0xFF000000 | (parseRgbHex(hex) ?? fallbackRgb);
}

int eventChromeBannerFromArgb(EventSkinChrome skin) {
  return eventChromeArgb(skin.bannerFrom, kEventSkinFallbackFrom);
}

int eventChromeBannerToArgb(EventSkinChrome skin) {
  return eventChromeArgb(skin.bannerTo, kEventSkinFallbackTo);
}

int eventChromeInkArgb(EventSkinChrome skin) {
  return eventChromeArgb(skin.ink, kEventSkinFallbackInk);
}

String eventChromeTitle(EventInfoModel event) {
  final name = event.name?.trim();
  if (name != null && name.isNotEmpty) return name;
  return event.code;
}

String eventChromeTagline(EventInfoModel event) {
  final custom = event.chrome.tagline?.trim();
  if (custom != null && custom.isNotEmpty) return custom;
  return event.chrome.skin.subtitle.trim();
}

String eventChromeTaglineLabel(EventInfoModel event) {
  return eventChromeTagline(event).toUpperCase();
}

int? eventLookThemeArgb(String? hex) {
  final n = parseRgbHex(hex ?? '');
  if (n == null) return null;
  return 0xFF000000 | n;
}

int eventLookFillArgb({
  required String? themeHex,
  required EventSkinChrome skin,
  required int index,
}) {
  final fromTheme = eventLookThemeArgb(themeHex);
  if (fromTheme != null) return fromTheme;
  return index.isEven
      ? eventChromeBannerFromArgb(skin)
      : eventChromeBannerToArgb(skin);
}
