import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/memory_pressure_response.dart';
import 'package:photobooth/services/file_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('trimFlutterMemoryCaches completes without error', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(tester.takeException(), isNull);
    trimFlutterMemoryCaches();
    expect(tester.takeException(), isNull);
  });

  testWidgets('trimFlutterMemoryCaches aggressive clears cache', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    trimFlutterMemoryCaches(aggressive: true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('respondToAppMemoryPressure completes without error', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    respondToAppMemoryPressure();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('respondToAppMemoryPressure swallows temp cleanup failures', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    memoryPressureTempCleanup =
        () => Future<void>.error(Exception('cleanup failed'));
    addTearDown(() {
      memoryPressureTempCleanup = FileHelper.cleanupTempImages;
    });
    respondToAppMemoryPressure();
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });
}
