import '../screens/theme_selection/theme_model.dart';

/// Client-side theme filtering (matches live web kiosk logic).
///
/// The server returns all kiosk themes; filter by [personCount] before display.
class ThemeFilter {
  /// Authoritative person count for filtering (defaults to solo when unknown).
  static int effectivePersonCount(int? personCount) => personCount ?? 1;

  /// Whether [theme] should appear for [personCount] (from preprocess).
  static bool showTheme(ThemeModel theme, int? personCount) {
    if (theme.isActive != true) return false;

    final count = effectivePersonCount(personCount);
    if (count == 1) {
      return theme.applicableSolo ?? theme.applicableSmallGroup ?? true;
    }
    if (count == 2) {
      return theme.applicableCouple ?? theme.applicableSmallGroup ?? true;
    }
    return theme.applicableLargeGroup ?? true;
  }

  static List<ThemeModel> filterForPersonCount(
    Iterable<ThemeModel> themes,
    int? personCount,
  ) {
    return themes.where((t) => showTheme(t, personCount)).toList();
  }
}
