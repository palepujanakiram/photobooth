# Asset Checklist

## App icon — ✅ already in this bundle

| File | Size | Use |
|---|---|---|
| `assets/icons/app-icon-1024.png` | 1024×1024 | iOS App Store + Play feature graphic source |
| `assets/icons/fotozen_app_icon.png` | source | Master FotoZen icon (in-app + listing) |
| `assets/icons/fotozen_ai_logo.png` | source | Marketing / banner use |

The Android `mipmap-*` and iOS `AppIcon.appiconset` are already populated in the project — no further work needed for the on-device icon.

For the **Play Store feature graphic** (1024×500, no transparency, mandatory), generate one from the master icon + a tagline ("Capture. Transform. Print.") — save to `assets/icons/play-feature-graphic-1024x500.png` once produced.

## Screenshots — ❌ to be captured

Drop them into `assets/screenshots-TODO/` as you produce them.

### Required minimums

| Store | Device class | Resolution | Min count | Recommended |
|---|---|---|---|---|
| Play Store | Phone | 1080×1920 (portrait) or 1920×1080 (landscape) | 2 | 5–8 |
| Play Store | 7-inch tablet | 1200×1920 | 1 | 3–5 |
| Play Store | 10-inch tablet | 1600×2560 | 1 | 3–5 |
| App Store | iPhone 6.7" | 1290×2796 | 3 | 5–10 |
| App Store | iPhone 6.5" | 1242×2688 | 3 | 5–10 |
| App Store | iPad Pro 12.9" (3rd gen+) | 2048×2732 | 3 | 5–10 |

> **Tip — use real kiosk footage.** The AI transformation result is the hero of this app. Screenshots from the simulator/emulator showing the static UI will under-sell it. Capture mid-session screens from a real kiosk: camera framing, theme picker, generation progress, and the final styled result side-by-side with the source photo.

### Recommended screen flow (5-screenshot story)

1. **Hero** — final AI-styled result on the result screen, with the original photo inset.
2. **Theme picker** — grid of 50+ themes.
3. **Live capture** — camera preview with framing guides.
4. **Payment** — UPI QR + amount.
5. **Print confirmation** — "Your print is ready!" screen with the photo preview.

For each screenshot, leave **0 px** border/letterboxing — Apple rejects screenshots with marketing chrome.

### Localized variants

For India-only v1.0, English screenshots are sufficient. Telugu / Hindi localization can be added in a later release.

### Capture commands (for the engineer)

Android emulator screenshot:
```bash
adb exec-out screencap -p > screenshots/play/phone-01.png
```

iOS simulator (from Xcode → Device → Screenshot, or):
```bash
xcrun simctl io booted screenshot screenshots/appstore/iphone-01.png
```

## Promo / preview video — optional but recommended

| Store | Spec | Recommended length |
|---|---|---|
| Play Store | YouTube URL, 30 s | 15–30 s |
| App Store | App Preview video (30 s, portrait), uploaded directly | 15–30 s |

Capture: a single uninterrupted recording of a kiosk session — capture → theme select → generation → result → print — at 1080p portrait.

## Checklist for the engineer to mark off

- [ ] Capture 5 phone screenshots (Play + App Store reuse)
- [ ] Capture 3 tablet/iPad screenshots
- [ ] Generate `play-feature-graphic-1024x500.png`
- [ ] Record optional 20-second app-preview video
- [ ] Drop everything into `assets/screenshots-TODO/` (rename folder when complete)
