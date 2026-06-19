import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/constants.dart';
import 'package:photobooth/utils/print_orientation.dart';

void main() {
  test('fromPersonCount solo is portrait', () {
    expect(
      PrintOrientation.fromPersonCount(1),
      PrintOrientation.portrait,
    );
    expect(
      PrintOrientation.fromPersonCount(null),
      PrintOrientation.portrait,
    );
  });

  test('fromPersonCount couple or group is landscape', () {
    expect(
      PrintOrientation.fromPersonCount(2),
      PrintOrientation.landscape,
    );
    expect(
      PrintOrientation.fromPersonCount(5),
      PrintOrientation.landscape,
    );
  });

  test('cardAspectRatio and printSize', () {
    expect(
      PrintOrientation.portrait.cardAspectRatio,
      AppConstants.kThemeSelectedCardAspectRatio,
    );
    expect(
      PrintOrientation.landscape.cardAspectRatio,
      AppConstants.kBeholdSingleResultDefaultAspectRatio,
    );
    expect(
      PrintOrientation.portrait.printSize,
      AppConstants.kPrintSizePortrait4x6,
    );
    expect(
      PrintOrientation.landscape.printSize,
      AppConstants.kPrintSizeLandscape6x4,
    );
  });

  test('tryParse', () {
    expect(PrintOrientation.tryParse('landscape'), PrintOrientation.landscape);
    expect(PrintOrientation.tryParse('Portrait'), PrintOrientation.portrait);
    expect(PrintOrientation.tryParse(''), isNull);
  });
}
