# Qlty quality process

Qlty ([qlty.sh](https://qlty.sh)) runs separately from SonarCloud. See [`docs/sonar-quality.md`](sonar-quality.md) for Sonar gates and remediation.

## CI coverage upload

[`.github/workflows/qlty.yml`](../.github/workflows/qlty.yml) on every push to `main` and on pull requests:

1. `flutter test --coverage` in `photobooth/`
2. Upload `photobooth/coverage/lcov.info` via [`qltysh/qlty-action/coverage@v2`](https://github.com/qltysh/qlty-action)

### GitHub secret (required)

1. In Qlty → your repository → **Settings** → create a **coverage token**.
2. In GitHub → **Settings → Secrets and variables → Actions** → add:
   - Name: `QLTY_COVERAGE_TOKEN`
   - Value: the token from Qlty

The upload step uses:

- `files: photobooth/coverage/lcov.info` (Flutter LCOV, not `target/lcov.info`)
- `format: lcov`
- `add-prefix: photobooth` so paths in the report match the monorepo (`lib/...` under `photobooth/`)

Without `QLTY_COVERAGE_TOKEN`, the **Qlty** workflow fails on upload. The **SonarCloud** workflow is unaffected.

## Local checks

```bash
cd photobooth
flutter test --coverage
# Report: photobooth/coverage/lcov.info
```

Optional: install [Qlty CLI](https://qlty.sh) and run from the repo root with [`.qlty/qlty.toml`](../.qlty/qlty.toml).

## Exclusions (3rd-party / vendored packages)

Path dependencies under `photobooth/packages/` are not app code. They are excluded in [`.qlty/qlty.toml`](../.qlty/qlty.toml):

- `photobooth/packages/camera_android_camerax/`
- `photobooth/packages/camera_native_details/`

Do not remove these unless you intend Qlty to analyze vendored forks.

## Relationship to SonarCloud

| | Qlty | SonarCloud |
|---|------|------------|
| Workflow | [`qlty.yml`](../.github/workflows/qlty.yml) | [`sonarcloud.yml`](../.github/workflows/sonarcloud.yml) |
| Secret | `QLTY_COVERAGE_TOKEN` | `SONAR_TOKEN` |
| Config | `.qlty/qlty.toml` | `photobooth/sonar-project.properties` |

Both workflows run tests independently today (duplicate `flutter test` per PR). That is intentional for separation; optimize later with a shared coverage artifact if CI time matters.
