import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/memory_pressure_response.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('trimFlutterMemoryCaches completes without error', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    expect(tester.takeException(), isNull);
    trimFlutterMemoryCaches();
    expect(tester.takeException(), isNull);
  });

  testWidgets('respondToAppMemoryPressure completes without error', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    respondToAppMemoryPressure();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
