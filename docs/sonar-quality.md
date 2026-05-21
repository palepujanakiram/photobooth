# SonarCloud quality process

Project: [palepujanakiram_photobooth](https://sonarcloud.io/project/overview?id=palepujanakiram_photobooth)

## Quality gate (new code)

| Metric | Target |
|--------|--------|
| Coverage | ≥ 80% |
| Duplicated lines | ≤ 3% |
| Security hotspots reviewed | 100% |

## New code definition (recommended)

In SonarCloud → **Project Settings → New Code**, prefer one of:

- **Previous version** or **Last release** — gate tracks changes since the last release (best for PRs).
- **Number of days** (e.g. **30**) — smaller scope than “Since 5 months ago”; easier to reach 80% coverage incrementally.

Avoid leaving **reference period = 5 months** unless you accept a multi-month test program for ~11k “new” lines.

Document any change to this setting in the PR that updates Sonar admin.

## Security hotspots (Phase 0 — manual, required for gate)

1. Open [Security Hotspots](https://sonarcloud.io/project/security_hotspots?id=palepujanakiram_photobooth).
2. For each hotspot: review, add a short comment, mark **Safe** or **Fixed**.
3. Gate requires **100% reviewed** — CI cannot do this step.

Checklist for reviewers:

- [ ] All hotspots reviewed
- [ ] No unresolved “To review” items on the PR branch

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
3. Security hotspot review in Sonar UI (see above)
4. Code smells by rule (`S3358` ternaries, `S3776` complexity, `S1192` literals)

## CI

[`.github/workflows/sonarcloud.yml`](../.github/workflows/sonarcloud.yml) runs `flutter test --coverage`, verifies `coverage/lcov.info` exists, then scans with `projectBaseDir: photobooth`. Coverage is read via [`sonar-project.properties`](../photobooth/sonar-project.properties) (`sonar.dart.lcov.reportPaths`).

If the gate shows **0% coverage** despite green CI, check the workflow log for the “Verify coverage report” step and Sonar scanner logs for LCOV import errors.

## Shared strings

Use [`lib/utils/app_strings.dart`](../photobooth/lib/utils/app_strings.dart) for duplicated user-facing and log literals.

## Exclusions

Generated and vendored paths are listed in `sonar-project.properties`. Do not add per-line suppressions without a comment in the PR.

## Phased remediation (in-repo)

| Phase | Focus |
|-------|--------|
| 0 | Hotspots (UI) + lcov CI check + new-code setting |
| 1 | Duplication ≤ 3% — API/logging + view extractions |
| 2 | Coverage ≥ 80% — utils/services tests, then ViewModels |
| 3 | Burn down new issues (S3776 → S3358 → S1192) |
