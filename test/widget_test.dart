// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:photobooth/main.dart';

void main() {
  testWidgets('PhotoBoothApp can be created with navigatorKey', (WidgetTester tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    // Verify required constructor argument can be provided.
    final app = PhotoBoothApp(navigatorKey: navigatorKey);
    expect(app, isA<PhotoBoothApp>());
  });
}
