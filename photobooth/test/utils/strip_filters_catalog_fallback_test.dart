import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/strip_models.dart';
import 'package:photobooth/utils/strip_filters_catalog_fallback.dart';

void main() {
  test('stripFiltersCatalogFallback exposes browsable looks', () {
    final catalog = stripFiltersCatalogFallback();
    expect(catalog.filters, isNotEmpty);
    expect(catalog.filters.any((f) => f.id == kDefaultStripFilterId), isTrue);
    expect(catalog.frames, isNotEmpty);
    expect(catalog.enableOsdScrub, isFalse);
  });
}
