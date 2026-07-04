import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/kiosk_page_route.dart';

void main() {
  test('KioskFadePageRoute uses a short fade transition', () {
    final route = KioskFadePageRoute<void>(
      page: const SizedBox.shrink(),
    );
    expect(route.transitionDuration, const Duration(milliseconds: 120));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 120));
  });
}
