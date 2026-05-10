# FotoZen Release Bundle — for Deployment Engineer

Everything needed to set up the **Google Play Console** and **App Store Connect** listings for the FotoZen photo-booth app.

App identity — confirmed against `pubspec.yaml`, `AndroidManifest.xml`, and `Info.plist`:

| Field | Value |
|---|---|
| App name (display) | **FotoZen AI** |
| Package / Bundle ID | `com.srisarani.fotozenai` |
| Current version | `0.1.0+11` (will bump to `1.0.0+1` for first production build) |
| Publisher | **Srisarani Ventures Private Limited** |
| Website | https://www.srisarani.com |
| Production server | https://fotozenai.fly.dev |
| Support email | support@fotozenai.com |

## What's in this bundle

| File | Purpose |
|---|---|
| `01-store-listing.md` | App name, taglines, short + long description, category, keywords. Drop straight into the listing forms. |
| `02-data-safety-android.md` | Field-by-field answers for the **Play Console "Data safety"** form. |
| `03-app-privacy-ios.md` | Field-by-field answers for the **App Store Connect "App Privacy"** questionnaire. |
| `04-permissions.md` | Every Android/iOS permission declared in the app, the user-visible string, and the justification to give a reviewer. |
| `05-asset-checklist.md` | Icons (✅ available in `assets/icons/`) and screenshots (❌ to be captured — guidance included). |
| `06-developer-account-info.md` | Company / registered office / GST / contact info for both store accounts. |
| `07-video-production-brief.md` | Single-shoot brief for both the 30 s YouTube/Play promo and the 15–30 s App Store App Preview. Spec sheets, shared shot list, two cut sheets, editor checklist. |
| `assets/icons/` | Master 1024×1024 app icon + source brand logos. |
| `assets/screenshots-TODO/` | Empty folder — drop captured screenshots here as they're produced. |
| `assets/video-raw/` | Empty folder — drop raw screen captures here from the engineer's recording session. |

## Public URLs (already live, shared earlier with Cashfree)

| Listing field | URL |
|---|---|
| Privacy Policy | https://fotozenai.fly.dev/privacy |
| Terms & Conditions | https://fotozenai.fly.dev/terms |
| Refunds & Cancellations | https://fotozenai.fly.dev/refunds |
| Services & Pricing | https://fotozenai.fly.dev/services |
| Contact | https://fotozenai.fly.dev/contact |
| Marketing site | https://www.srisarani.com |

> **One thing to flag with Raghav before submission:** the privacy and terms pages currently live on `fotozenai.fly.dev`. Some Play / App Store reviewers prefer the policy be hosted on the same domain as the publisher's main brand. Either is acceptable — confirm whether to keep `fly.dev` or also publish a copy on `www.srisarani.com` or a future `fotozenai.com`.

## Outstanding items the engineer needs from Raghav

1. **Screenshots** — at least 3 phone + 3 tablet captures, ideally 5–8. See `05-asset-checklist.md` for spec.
2. **Promo/feature graphic** for Play Store (1024×500 PNG/JPG, no transparency).
3. **Optional preview video** (15–30 s) — not required, recommended for AI/photo apps.
4. **Apple Developer Team selection** in Xcode signing.
5. **Android upload keystore** (currently still set to debug — see top-level `RELEASE_CHECKLIST.md` Section 2 for key generation steps).
6. **Reviewer demo path** — App Store reviewers cannot run a kiosk-bound build. Decide whether to ship a "demo mode" build for review, or include a reviewer-friendly kiosk code with sample data.

## Cross-references

- `../RELEASE_CHECKLIST.md` — broader engineering checklist (signing, version bump, kiosk-vs-consumer decision).
