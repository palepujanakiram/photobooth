// Updates pubspec `version:` before release builds.
//
// Version name: YEAR.MONTH.DAY (local calendar date).
// Build number:
//   - Pass `--build-number=N` (Fastlane sets this from App Store Connect / Google Play).
//   - Otherwise increment the existing +suffix in pubspec (local builds only).
//
// Run from package root: dart run tool/sync_build_version.dart
import 'dart:io';

void main(List<String> args) {
  final dryRun = args.contains('--dry-run');
  int? explicitBuild;
  for (final arg in args) {
    if (arg.startsWith('--build-number=')) {
      explicitBuild = int.tryParse(arg.split('=').last.trim());
      if (explicitBuild == null || explicitBuild < 1) {
        stderr.writeln('sync_build_version: invalid --build-number value');
        exitCode = 1;
        return;
      }
    }
  }

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
  final versionName = '${now.year}.${now.month}.${now.day}';

  final currentFull = m.group(1)!.trim();
  final build = explicitBuild ?? _nextLocalBuildNumber(currentFull);

  final newVersion = '$versionName+$build';
  if (dryRun) {
    stdout.writeln('Would set version: $newVersion');
    return;
  }

  final updated = text.replaceFirst(versionRe, 'version: $newVersion');
  pubspec.writeAsStringSync(updated);
  stdout.writeln('sync_build_version: version: $newVersion');
}

int _nextLocalBuildNumber(String currentFull) {
  final plus = currentFull.split('+');
  if (plus.length == 2) {
    return (int.tryParse(plus[1].trim()) ?? 0) + 1;
  }
  return 1;
}
