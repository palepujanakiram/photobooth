import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_behold_aspect.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/print_orientation.dart';

void main() {
  testWidgets('beholdSingleResultCardAspectRatio follows print orientation', (
    tester,
  ) async {
    final vm = PhotoGenerateViewModel();
    vm.setPrintOrientation(PrintOrientation.landscape);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final aspect = beholdSingleResultCardAspectRatio(
              context,
              vm,
              maxWidth: 360,
              maxHeight: 420,
            );
            expect(aspect, AppConstants.kBeholdSingleResultDefaultAspectRatio);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    vm.setPrintOrientation(PrintOrientation.portrait);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            final aspect = beholdSingleResultCardAspectRatio(
              context,
              vm,
              maxWidth: 360,
              maxHeight: 420,
            );
            expect(aspect, AppConstants.kThemeSelectedCardAspectRatio);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
}
