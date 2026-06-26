import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';

void main() {
  group('behold entrance flag', () {
    test('consumes once', () {
      final vm = PhotoGenerateViewModel();
      expect(vm.consumeBeholdEntranceFromProgressReveal(), isFalse);
      vm.markBeholdEntranceFromProgressReveal();
      expect(vm.consumeBeholdEntranceFromProgressReveal(), isTrue);
      expect(vm.consumeBeholdEntranceFromProgressReveal(), isFalse);
    });
  });
}
