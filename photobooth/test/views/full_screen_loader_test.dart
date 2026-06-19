import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/views/widgets/full_screen_loader.dart';

void main() {
  testWidgets('shows title and subtitle without debug info', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FullScreenLoader(
            text: 'Processing Your Photo',
            subtitle: 'Uploading…',
            autonomousElapsed: true,
          ),
        ),
      ),
    );

    expect(find.text('Processing Your Photo'), findsOneWidget);
    expect(find.text('Uploading…'), findsOneWidget);
    expect(find.text('0s'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('1s'), findsOneWidget);
  });
}
