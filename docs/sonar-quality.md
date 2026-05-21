# SonarCloud quality process

Project: [palepujanakiram_photobooth](https://sonarcloud.io/project/overview?id=palepujanakiram_photobooth)

## Before every PR

```bash
cd photobooth
dart analyze
flutter test --coverage
```

Fix SonarLint issues in the IDE (connected mode: `palepujanakiram` / `palepujanakiram_photobooth`).

Do not merge if the SonarCloud PR quality gate fails.

## Triage order

1. Quality gate blockers (coverage, duplication, hotspots, reliability)
2. Bugs and vulnerabilities
3. Security hotspot review in Sonar UI
4. Code smells by rule (`S3358` ternaries, `S3776` complexity, `S1192` literals)

## CI

[`.github/workflows/sonarcloud.yml`](../.github/workflows/sonarcloud.yml) runs `flutter test --coverage` before the Sonar scan. Coverage is read from `photobooth/coverage/lcov.info` via [`sonar-project.properties`](../photobooth/sonar-project.properties).

## Shared strings

Use [`lib/utils/app_strings.dart`](../photobooth/lib/utils/app_strings.dart) for duplicated user-facing and log literals.

## Exclusions

Generated and vendored paths are listed in `sonar-project.properties`. Do not add per-line suppressions without a comment in the PR.
