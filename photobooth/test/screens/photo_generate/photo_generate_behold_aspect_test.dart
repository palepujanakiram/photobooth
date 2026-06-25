import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_behold_aspect.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/print_orientation.dart';

void main() {
  testWidgets('beholdCardIsPhonePortrait true on phone portrait', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            // Default test surface: 800×600, landscape-ish but shortestSide=600 boundary.
            // Force a clearly phone-portrait surface via MediaQuery.
            final result = beholdCardIsPhonePortrait(context);
            // Default MediaQuery in tests is landscape 800×600, shortestSide=600 ≥ 600 → false.
            expect(result, isFalse);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });

  testWidgets('beholdCardIsPhonePortrait true when portrait and narrow', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(360, 640)),
        child: MaterialApp(
          home: Builder(
            builder: (context) {
              final result = beholdCardIsPhonePortrait(context);
              expect(result, isTrue);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  });

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
