import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/staff/staff_auth_helpers.dart';
import 'package:photobooth/utils/exceptions.dart';

void main() {
  group('StaffAuthHelpers.isAuthFailure', () {
    test('true for HTTP 401', () {
      expect(
        StaffAuthHelpers.isAuthFailure(ApiException('Nope', 401)),
        isTrue,
      );
    });

    test('true for Unauthorized message without status', () {
      expect(
        StaffAuthHelpers.isAuthFailure(ApiException('Unauthorized')),
        isTrue,
      );
    });

    test('true for expired / log in copy', () {
      expect(
        StaffAuthHelpers.isAuthFailure(
          ApiException('Staff session expired. Please log in again.'),
        ),
        isTrue,
      );
    });

    test('false for unrelated errors', () {
      expect(
        StaffAuthHelpers.isAuthFailure(ApiException('Network error', 500)),
        isFalse,
      );
      expect(
        StaffAuthHelpers.isAuthFailure(ApiException('Not found', 404)),
        isFalse,
      );
    });
  });
}
