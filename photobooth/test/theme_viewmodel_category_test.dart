import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/theme_selection/theme_selection_viewmodel.dart';

void main() {
  test('getCategoryDisplayName title-cases unknown category ids', () {
    final vm = ThemeViewModel();
    expect(vm.getCategoryDisplayName('super_hero'), 'Super Hero');
    expect(vm.getCategoryDisplayName('All'), 'All');
    expect(vm.getCategoryDisplayName('royal'), 'Royal');
  });
}
