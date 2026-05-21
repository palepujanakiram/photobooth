import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/app_strings.dart';
import 'package:photobooth/utils/logger_stack_frame.dart';

void main() {
  test('parseLoggerCallSite parses parenthesized frame with line number', () {
    final site = parseLoggerCallSite(
      StackTrace.fromString(
        '#0      capturePhoto (photo_capture_viewmodel.dart:88:15)\n',
      ),
    );
    expect(site?.fileName, 'photo_capture_viewmodel.dart');
    expect(site?.functionName, 'capturePhoto');
    expect(site?.lineNumber, '88');
  });

  test('parseLoggerCallSite parses standard dart frame', () {
    final site = parseLoggerCallSite(
      StackTrace.fromString(
        '#0      myFunction (package:photobooth/screens/home/home_view.dart:42:10)\n'
        '#1      other (package:photobooth/utils/logger.dart:10:5)\n',
      ),
    );
    expect(site, isNotNull);
    expect(site!.fileName, 'home_view.dart');
    expect(site.functionName, 'myFunction');
    expect(site.lineNumber, '42');
    expect(site.location, contains('home_view.dart'));
  });

  test('parseLoggerCallSite parses file:line function frame without hash prefix', () {
    final site = parseLoggerCallSite(
      StackTrace.fromString(
        'lib/utils/constants.dart:12:5  main\n',
      ),
    );
    expect(site, isNotNull);
    expect(site!.fileName, 'constants.dart');
    expect(site.functionName, 'main');
    expect(site.lineNumber, '12');
  });

  test('parseLoggerCallSite uses fallback when primary frames are logger', () {
    final site = parseLoggerCallSite(
      StackTrace.fromString(
        '#0      AppLogger.debug (${AppStrings.loggerFileName}:20:5)\n'
        '#1      runTest (package:photobooth/test/foo_test.dart:12:7)\n',
      ),
    );
    expect(site, isNotNull);
    expect(site!.fileName, 'foo_test.dart');
  });

  test('parseLoggerCallSite returns null for empty trace', () {
    expect(parseLoggerCallSite(StackTrace.fromString('')), isNull);
  });

  test('_fileNameOnly strips package prefix via public parse', () {
    final site = parseLoggerCallSite(
      StackTrace.fromString(
        '#0      fn (package:photobooth/lib/utils/constants.dart:1:1)\n',
      ),
    );
    expect(site?.fileName, 'constants.dart');
  });
}
