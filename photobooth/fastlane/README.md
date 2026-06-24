# Fastlane (Android + iOS)

Run from `photobooth/`:

```sh
bundle install
```

## generatebuild (build + upload)

Same lane name on both platforms — Fastlane picks the store from the platform:

| Command | Output | Upload destination |
|---------|--------|-------------------|
| `bundle exec fastlane android generatebuild` | AAB | Google Play Console (+ Firebase App Distribution) |
| `bundle exec fastlane ios generatebuild` | IPA | App Store Connect (TestFlight) |

Each `generatebuild` lane:

1. Syncs version (`YEAR.MONTH.DAY+build`) from the store API
2. Builds the release artifact
3. Uploads to the platform store

## Build only (no upload)

```sh
bundle exec fastlane android build
bundle exec fastlane ios build
```

## Versioning

- **Version name:** `YEAR.MONTH.DAY` (e.g. `2026.6.24`)
- **iOS build number:** latest TestFlight build for that version + 1
- **Android version code:** highest version code across Play tracks + 1 (never resets; Play requirement)

## Configuration

Edit distribution settings at the top of [`Fastfile`](Fastfile):

- **Android:** `FIREBASE_TOKEN`, `PLAY_STORE_JSON_KEY_PATH`, etc.
- **iOS:** `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, API key at `fastlane/credentials/AuthKey_3Y28UQD6SG.p8`

iOS requires macOS with Xcode. Android `generatebuild` also pushes to Firebase App Distribution after Play Console upload.
