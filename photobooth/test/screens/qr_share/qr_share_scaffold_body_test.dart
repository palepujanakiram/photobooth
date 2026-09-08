import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/qr_share/qr_share_scaffold_body.dart';
import 'package:photobooth/utils/app_strings.dart';

void main() {
  testWidgets('close and Start again both fire onExit', (tester) async {
    var exits = 0;
    final seconds = ValueNotifier<int>(36);
    addTearDown(seconds.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: QrShareScaffoldBody(
          qrData: 'https://share.example/s/1',
          longUrl: '',
          expiry: '',
          headline: 'Scan this QR on your phone to download a digital copy.',
          waLine: '',
          secondsLeftListenable: seconds,
          onExit: () => exits += 1,
        ),
      ),
    );

    await tester.tap(find.byIcon(CupertinoIcons.xmark));
    await tester.pump();
    expect(exits, 1);

    await tester.tap(find.text(AppStrings.qrShareStartAgain));
    await tester.pump();
    expect(exits, 2);
  });
}
