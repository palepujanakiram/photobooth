# FotoZen — App Store Release Checklist

A FotoZen-specific adaptation of the standard Flutter release flow. Reflects the actual state of `repo/photobooth` as of v0.1.0+11 — items already done are marked, items that need attention are flagged.

## 0. Decide what you're shipping first

The photobooth app today is a **kiosk** — running on operator-owned tablets at malls/SEZs. Before going to the stores, get clear on which of these you're publishing:

- **Operator distribution build** — for staff to side-load or pull from internal track. Doesn't strictly need public store listing; Play Console internal/closed testing is enough.
- **Public consumer build** — would require trimming kiosk-only flows (single-tenant config, hardcoded device assumptions, external-camera dependencies), and is a different product positioning than "Generative Media OS for Physical Spaces."
- **Both** — separate flavors, separate package IDs (e.g. `com.srisarani.fotozenai.kiosk` vs `com.srisarani.fotozenai`).

Most of this checklist assumes the **operator distribution** path, which is the lowest-friction first release.

## 1. App identity (current state)

| Field | Android | iOS | Notes |
|---|---|---|---|
| Package / Bundle ID | `com.srisarani.fotozenai` ✅ | `com.srisarani.fotozenai` ✅ | Consistent. Good. |
| Display name | "Fotozen AI" ✅ | "Photo Booth" ❌ | **Mismatch — fix iOS `CFBundleDisplayName` to "FotoZen AI"** |
| Version | `0.1.0+11` ⚠️ | `0.1.0+11` ⚠️ | Bump to `1.0.0+1` for first production release |
| Icon | `@mipmap/ic_launcher` | Runner icon set | Verify both use the FotoZen logo (see `lib/images/fotozen_app_icon.png`) |

In `pubspec.yaml`:

```yaml
version: 1.0.0+1   # bump from 0.1.0+11
```

`publish_to: 'none'` is fine — it only blocks publishing to pub.dev, not to the app stores.

## 2. Signing — **biggest blocker right now**

`android/app/build.gradle` currently has:

```groovy
release {
    signingConfig signingConfigs.debug   // ← Play Store will reject this
    minifyEnabled false
}
```

Required before Play Console upload:

1. Generate an upload keystore:
   ```bash
   keytool -genkey -v -keystore ~/fotozen-upload.jks \
     -keyalg RSA -keysize 2048 -validity 10000 \
     -alias fotozen-upload
   ```
   Store the `.jks` somewhere durable (1Password / encrypted backup) — losing it means losing the ability to push updates without a key reset request to Google.
2. Create `android/key.properties` (already in `.gitignore` per Flutter convention; verify):
   ```
   storePassword=...
   keyPassword=...
   keyAlias=fotozen-upload
   storeFile=/absolute/path/fotozen-upload.jks
   ```
3. Wire it into `build.gradle` — replace the debug signingConfig with a proper release block reading from `key.properties`. The standard Flutter docs snippet works as-is.
4. Enroll in **Play App Signing** when uploading the first AAB; Google holds the actual signing key, you only ever need the upload key.

iOS signing is handled by Xcode automatic signing once the Apple Developer team is selected on the Runner target.

## 3. Permissions audit

Already declared (`AndroidManifest.xml` + `Info.plist`):

- Camera, microphone, internet, notifications, photo library read/write

Things to double-check before submission:

- **iOS usage strings** — current camera string says "external camera," which is accurate for the kiosk but reads oddly on a phone. If the build is also targeted at non-kiosk devices, soften to: *"FotoZen uses the camera to capture your photos for AI-styled portraits."*
- **Microphone** — only needed for the external-camera init path. If the build doesn't use external cameras (e.g. iOS-only consumer build), remove `NSMicrophoneUsageDescription` and the permission entirely; otherwise Apple reviewers will ask why a photo booth needs the mic.
- **Storage permissions on Android 33+** — already correctly scoped via `maxSdkVersion="32"` + `READ_MEDIA_IMAGES`. Good.

## 4. Privacy & legal — **the FotoZen-specific bulk**

Because the app captures faces, sends them to a third-party-hosted ML pipeline (RunPod A40 → Flux.1 + PuLID), and processes payments, this needs more care than a typical Flutter app.

### 4.1 Privacy policy must explicitly cover

- **What's captured**: live photos of the user's face.
- **Where it's processed**: photos are uploaded to `zenai` server and a GPU pipeline on RunPod for AI transformation.
- **Biometric processing disclosure**: PuLID extracts facial features for identity preservation. Under India's DPDP Act 2023, biometric data is treated as sensitive personal data — explicit consent + purpose limitation required. Apple's App Review (5.1.2) and Play's User Data policy both require a clear disclosure.
- **Retention**: state how long source photos and generated outputs are kept on the server, and the deletion window. (Decision needed: is it 24h? 7 days? Until session ends?)
- **Third-party processors**: RunPod, Supabase, Google (per the monthly bills memory), Replit. Listed by name with links to their policies.
- **No training**: explicit statement that user photos are not used to train models, if that's the case.
- **Payment data**: handled offline / by payment processor — app does not store card details.
- **Sharing**: photos shared via QR / WhatsApp leave the app boundary at the user's request.

Host this at a stable URL (e.g. `https://fotozen.ai/privacy`) — both stores require a reachable URL in the listing.

### 4.2 In-app consent

- The existing `lib/screens/terms_and_conditions` flow needs to (a) require active acceptance before camera capture, not just be available, and (b) include the biometric/AI processing disclosure inline, not buried in a linked T&C.
- For minors: kiosks are deployed in malls. Either explicitly require operator gating for under-18 users, or build in an age-gate. Apple's App Review pays attention to anything that captures images of children.

### 4.3 Apple-specific gotchas

- **Payment for digital content** must use IAP. Since FotoZen photos are arguably a digital good, Apple may push back on offline-only payment. Mitigations: position the print as a physical good (which it is), or accept that the iOS build won't process payment in-app and is operator-mediated. Decide before submission — it's the most common rejection reason for this category.
- **App Tracking Transparency**: not currently using IDFA, so no `NSUserTrackingUsageDescription` needed. Confirm no analytics SDKs were pulled in via Crashlytics that would change this.
- **Encryption export compliance**: standard Flutter app, set `ITSAppUsesNonExemptEncryption=false` in `Info.plist` if not using custom crypto.

### 4.4 Play-specific gotchas

- **Data Safety form** in Play Console must declare: photo collection, biometric processing, location (if any), and payment data — even though payment is offline, Play wants you to declare it.
- **Sensitive permissions disclosure** if camera is core (it is) — straightforward, but the form is mandatory.

## 5. Store listing assets

Prepare once, reuse for both stores:

- App icon (1024×1024 for App Store, 512×512 + adaptive for Play)
- Screenshots: at minimum 3, ideally 5–8. Worth shooting these on the actual kiosk in operation rather than mocking them in the simulator — the AI-styled output is the hero.
- Short description (80 char) — emphasize the experience, not the tech: "Capture, transform, print — AI-styled portraits in 60 seconds."
- Long description — lead with the venue use case (events, malls, activations) since that's the actual operator audience.
- Promo video (optional but recommended for AI/photo apps — the transformation is the demo).
- Support email + privacy policy URL + (Play only) website URL.

## 6. Build commands

Pre-flight on every release:

```bash
flutter doctor
flutter clean
flutter pub get
flutter analyze
flutter test
```

Android (after signing is wired up):

```bash
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab
```

iOS (Mac + Xcode required):

```bash
flutter build ipa --release
# → build/ios/ipa/photobooth.ipa
# Then upload via Xcode Organizer or `xcrun altool`
```

`fastlane/` is already set up in this repo — once signing is configured, the existing Fastfile can automate the upload step.

## 7. Recommended release path

1. Wire up Android release signing (Section 2).
2. Fix iOS display name + decide on mic permission (Section 1, 3).
3. Bump version to `1.0.0+1`.
4. Publish privacy policy URL + update T&C screen with biometric disclosure.
5. **Android internal testing** track — push first AAB, install on a test kiosk, verify end-to-end: camera → upload → RunPod → result → QR share → payment.
6. **Android closed testing** — share with the field team running the SEZ deployments.
7. **iOS TestFlight** — same end-to-end test on iOS, plus reviewer-friendly demo account if needed.
8. Fix issues, bump build number each upload (`1.0.0+2`, `+3`, ...).
9. Submit to **production** on both stores, staggered (Play first, App Store after — App Review is the long pole).

## 8. Open decisions to lock before submission

- Photo retention window on the server (drives the privacy policy text).
- iOS payment story (IAP vs operator-mediated vs no iOS build for now).
- Whether v1.0 supports consumer install or remains operator-only (drives package ID + listing copy).
- Public privacy policy + T&C URLs.
- Support email and developer account name visible on the listings.

---

**Status snapshot:** package IDs ✅, fastlane scaffolding ✅, permissions mostly ✅, terms screen ✅. **Blockers:** release signing config, iOS display name mismatch, version bump, privacy policy hosting + biometric/AI disclosure copy.
