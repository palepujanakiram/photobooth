// Updates pubspec `version:` from [DateTime.now] and increments the +build counter.
//
// Encoding matches [ClientIdentification.formatClientVersionLabel]:
//   YEAR.MONTH.PATCH+buildNumber
//   PATCH = day×10000 + hour×100 + minute (24h local time)
//
// Run from package root: dart run tool/sync_build_version.dart
import 'dart:io';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  final pubspec = File('pubspec.yaml');
  if (!pubspec.existsSync()) {
    stderr.writeln('sync_build_version: pubspec.yaml not found (cwd: ${Directory.current.path})');
    exitCode = 1;
    return;
  }

  final text = pubspec.readAsStringSync();
  final versionRe = RegExp(r'^version:\s*([^\s#]+)\s*$', multiLine: true);
  final m = versionRe.firstMatch(text);
  if (m == null) {
    stderr.writeln('sync_build_version: no version: line found in pubspec.yaml');
    exitCode = 1;
    return;
  }

  final now = DateTime.now();
  final major = now.year;
  final minor = now.month;
  final patch = now.day * 10000 + now.hour * 100 + now.minute;

  final currentFull = m.group(1)!.trim();
  var build = 1;
  final plus = currentFull.split('+');
  if (plus.length == 2) {
    build = (int.tryParse(plus[1].trim()) ?? 0) + 1;
  }

  final newVersion = '$major.$minor.$patch+$build';
  if (dryRun) {
    stdout.writeln('Would set version: $newVersion');
    return;
  }

  final updated = text.replaceFirst(versionRe, 'version: $newVersion');
  pubspec.writeAsStringSync(updated);
  stdout.writeln('sync_build_version: version: $newVersion');
}
