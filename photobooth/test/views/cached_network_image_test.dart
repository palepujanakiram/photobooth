import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/views/widgets/cached_network_image.dart';

import '../helpers/tiny_jpeg.dart';

void main() {
  testWidgets('renders on-device Classic data JPEGs without a network fetch',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CachedNetworkImage(
          imageUrl: kTinyJpegDataUrl,
          fit: BoxFit.contain,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(CupertinoIcons.photo), findsNothing);
  });
}
