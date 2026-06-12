import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/debug_overlay_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('copyDebugPanelText writes to clipboard', (tester) async {
    final messengerKey = GlobalKey<ScaffoldMessengerState>();
    String? clipboardText;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map<Object?, Object?>)['text'] as String?;
      }
      return null;
    });

    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messengerKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => copyDebugPanelText(context, 'line one\nline two'),
              child: const Text('copy'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('copy'));
    await tester.pump();

    expect(clipboardText, 'line one\nline two');
    expect(find.text('Copied to clipboard'), findsOneWidget);
  });
}
