# Android Play Store AAB Release Guide (FotoZen)

This guide explains the exact steps to generate a Play Store compliant `.aab` and how to safely preserve signing keys.

## 1) One-time setup: create upload keystore

Run from any terminal:

```bash
keytool -genkey -v -keystore android/keystore/fotozen-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias fotozen-upload
```

Keep these values safe:
- Keystore file: `photobooth/android/keystore/fotozen-upload.jks`
- Keystore password (`storePassword`)
- Key password (`keyPassword`)
- Alias: `fotozen-upload`

## 2) Create `keystore/key.properties` for local signing

From repo root:

```bash
cd photobooth
cp android/key.properties.example android/keystore/key.properties
```

Edit `android/keystore/key.properties`:

```properties
storePassword=<your keystore password>
keyPassword=<your key password>
keyAlias=fotozen-upload
storeFile=../keystore/fotozen-upload.jks
```

Notes:
- `storeFile` is resolved from `android/app`, so `../keystore/...` points to `android/keystore`.
- `android/keystore/key.properties` is used by Gradle for release signing.

## 3) Bump app build number before each upload

Open `pubspec.yaml` and increase the number after `+` in `version`.

Example:
- Old: `version: 2026.5.100012+13`
- New: `version: 2026.5.100012+14`

## 4) Run preflight checks

```bash
cd photobooth
flutter doctor
flutter pub get
dart analyze
flutter test
```

Optional:

```bash
dart run tool/verify_coverage_scope.dart
```

## 5) Build release app bundle

```bash
cd photobooth
flutter build appbundle --release
```

Output:

`build/app/outputs/bundle/release/photobooth-release.aab`

## 6) Upload to Play Console

1. Go to Google Play Console.
2. Open app (`com.srisarani.fotozenai`).
3. Go to Internal testing (recommended first upload).
4. Create release and upload `photobooth-release.aab`.
5. Complete release notes and rollout.
6. Enable Play App Signing if prompted.

---

## Keystore backup policy (important)

Do **not** commit raw `.jks` files to git.
Do **not** commit plain `.zip` backups of `.jks` (zip is not secure encryption by default).

### Recommended

- Keep primary `.jks` in a secure local path.
- Store passwords and alias in a password manager.
- Keep an encrypted off-repo backup (1Password secure note/attachment, encrypted drive, etc.).

### If you must preserve in repository

Only commit an encrypted artifact (for example `.age` or `.gpg`), never raw `.jks`.

Example using `age`:

```bash
# Encrypt keystore
age -p -o android-upload-keystore.jks.age photobooth/android/keystore/fotozen-upload.jks

# Decrypt when needed
age -d -o photobooth/android/keystore/fotozen-upload.jks android-upload-keystore.jks.age
```

If using this approach, store the decryption passphrase in a secure password manager and restrict repository access.

## Quick troubleshooting

- Play says "signed in debug mode": verify `android/keystore/key.properties` exists and rebuild.
- "Version code already used": increment `+<build>` in `pubspec.yaml`.
- Build fails with keystore path: verify `storeFile` absolute path and file exists.
