# FotoZen — Video Production Brief

One document, two deliverables, single shoot. Captures all needed footage from screen recordings, then edits twice — once for **YouTube + Play Store** (30 s, marketing-friendly) and once for **App Store App Preview** (15–30 s, strict Apple rules).

> **Source assumption:** No live kiosk footage available. Everything is screen-recording-driven. This is fine for App Store (Apple actually *prefers* it), and acceptable for YouTube/Play with strong on-screen text + music.

## 1. Platform specs

| Spec | YouTube / Play Store | App Store App Preview |
|---|---|---|
| Length | 30 s exact | 15–30 s |
| Aspect | 16:9 landscape (YouTube), or 9:16 portrait if shooting only for Play | 9:16 portrait, **mandatory** |
| Resolution | 1920×1080 min, 4K preferred | 886×1920 (iPhone 6.5") **or** 1080×1920 (iPhone 6.7"). Upload all sizes you can produce. |
| Frame rate | 30 fps | 30 fps |
| Codec / container | H.264 MP4 | H.264 MP4 (.mov also OK) |
| Max file size | 256 MB (Play); YouTube no practical cap | 500 MB |
| Audio | Required (music + optional VO) | Optional. **No audio is the safest choice** — App Review reliably approves silent App Previews. |
| Captions | Burned-in on-screen text fine | Burned-in text fine; do **not** include device chrome (status bar replicas, etc.) |

## 2. Apple rejection landmines (read before editing the App Preview cut)

These are the most common reasons App Previews get rejected. Avoid them.

1. **No prices on screen.** Showing "₹250" anywhere in the App Preview will be rejected. Save price callouts for the YouTube cut.
2. **No "Download Now" / "Buy Now" / "Tap to Try" CTAs** anywhere in the video.
3. **No real-world footage of the kiosk hardware, customers, or printer.** App Previews must be ≥80% screen content from inside the app. Lifestyle B-roll → YouTube only.
4. **No competitor or platform names** ("Available on the App Store", "Made for iPhone" etc.) in the video itself.
5. **No animated logos at the end longer than 1 s.** Apple wants the in-app experience, not a TV-ad outro.
6. **Don't show launch screens / splash for more than ~1 s.** Reviewers consider it "loading".
7. **Music must be cleared.** Use Apple Music for Apps, Artlist, Epidemic Sound, or YouTube Audio Library — never YouTube-Music-rip.

## 3. Shared shot list — capture once, use for both cuts

These are the raw clips the editor needs. Capture each on the iOS simulator (`xcrun simctl io booted recordVideo`) or Android emulator (`adb shell screenrecord`) — whichever produces cleaner output for that screen.

| # | Shot | Source screen (`lib/screens/`) | Action to record | Duration to capture | Used in |
|---|---|---|---|---|---|
| A | Brand intro — logo emerges | `splash` | Boot → splash held still for 1 s | 2 s | YouTube only |
| B | Theme picker scroll | `theme_selection` / `theme_slideshow` | Slow vertical scroll through theme grid; pause briefly on a recognisable theme | 6 s | Both |
| C | Theme tap-to-select | `theme_selection` | Tap "Renaissance" (or similar visually striking theme) | 1.5 s | Both |
| D | Camera framing | `photo_capture` | Camera live preview with framing guides; subtle motion (hand on edge of frame OK) | 4 s | Both |
| E | Capture trigger | `photo_capture` | Countdown 3-2-1, shutter flash | 3 s | Both |
| F | Photo review | `photo_review` | Captured photo appears, "Looks good?" interaction | 2 s | Both |
| G | Generation in progress | `photo_generate` | Progress UI, animated states | 4 s | Both |
| H | **Hero reveal — AI result** | `result` | Generated image fades / wipes into view | 4 s | Both (most important shot) |
| I | Side-by-side compare | `result` | If the result screen has a before/after toggle, capture it | 3 s | Both |
| J | QR / share screen | `qr_share` | QR code appears, "Scan to download" UI | 3 s | YouTube only (App Preview shouldn't show external sharing) |
| K | Thank-you screen | `thank_you` | "Your photo is ready!" UI | 2 s | YouTube only |

**Total raw captured:** ~35 s of usable clips. Plenty of room to cut both videos.

### Capture commands

iOS Simulator (best for App Preview — Apple wants iOS-recorded video):

```bash
# Start recording (Cmd+C to stop)
xcrun simctl io booted recordVideo \
  --codec=h264 --type=mp4 \
  ~/fotozen-shoot/raw/ios-simulator-$(date +%H%M%S).mp4
```

Android Emulator (best for Play / YouTube cut):

```bash
adb shell screenrecord --bit-rate 8000000 --time-limit 30 \
  /sdcard/fotozen-shoot.mp4
adb pull /sdcard/fotozen-shoot.mp4 ~/fotozen-shoot/raw/
```

> Tip: Run captures at the maximum simulator/emulator resolution. Downscale in the edit, never upscale.

### Set-up before recording

- Use a clean kiosk binding seeded with sample photos so the AI generation completes quickly and reliably.
- Disable any "DEBUG" overlays (Flutter banner, performance overlay).
- Hide system clock / battery status — App Store rejects videos with simulated system UI.
- For the iOS sim, use a 6.5" or 6.7" iPhone profile (matches App Preview spec).
- Use a single, visually striking theme for shots B/C/H — consistent across all takes.
- For Shot H (hero reveal), if the actual result screen reveal animation isn't dramatic enough, **capture the still** and let the editor add a subtle reveal in post.

## 4. Cut sheet — YouTube / Play Store (30 s)

Beat-by-beat. Shot letters reference the table above.

| Time | Shot | On-screen text (large, sans-serif, bottom-third) | Audio / SFX |
|---|---|---|---|
| 0:00 – 0:02 | A — splash logo | (FotoZen AI logo only) | Music in, soft swell |
| 0:02 – 0:05 | B — theme scroll | **"50+ AI styles."** | Music continues |
| 0:05 – 0:07 | C — theme tap | **"Pick a look."** | Subtle UI tap SFX |
| 0:07 – 0:11 | D — camera framing | **"Snap your photo."** | Music continues |
| 0:11 – 0:14 | E — capture countdown + flash | (no text — let the flash punctuate) | Shutter SFX |
| 0:14 – 0:18 | G — generating | **"AI does the magic."** | Music swells |
| 0:18 – 0:24 | **H — hero AI result** | **"In 60 seconds."** | Music peaks; brief beat of silence then resumes |
| 0:24 – 0:27 | J — QR share | **"Print it. Share it. Keep it."** | Music continues |
| 0:27 – 0:30 | End card (static) | **"FotoZen AI" logo + ₹250 / photo + "Find a kiosk: srisarani.com"** | Music tails out |

**Music vibe:** upbeat electronic / cinematic build, no vocals. ~110 BPM. Royalty-free options:

- Epidemic Sound — search "playful tech" or "cinematic build"
- Artlist — "pop / playful" category
- YouTube Audio Library — free, search "uplifting"

**Voice-over:** optional, recommend skipping for v1.0 — on-screen text + music is faster to produce and localises easier.

**End-card detail:**

- Background: solid brand colour (pull from the FotoZen logo)
- Logo top-third
- "₹250 / photo" middle (only safe in YouTube/Play cut)
- "Find a kiosk: srisarani.com" bottom
- Hold for full 3 s

## 5. Cut sheet — App Store App Preview (20 s, strict)

Same source clips, no end card, no prices, no real-world inserts, ideally **silent** (Apple has approved my last several silent App Previews on first submit — far lower rejection risk).

| Time | Shot | On-screen text (only if needed; keep minimal) | Notes |
|---|---|---|---|
| 0:00 – 0:03 | B — theme scroll | "50+ AI styles" — small, top of frame | OK to include text |
| 0:03 – 0:05 | C — theme tap | (no text) | UI sound effect OK if going with audio |
| 0:05 – 0:08 | D — camera framing | "Snap your photo" | Keep frame clean |
| 0:08 – 0:11 | E — countdown + flash | (no text) | Flash should be the punctuation |
| 0:11 – 0:15 | G — generating | "AI styles your photo" | |
| 0:15 – 0:20 | **H — hero AI result** | "Done in seconds" | Hold the result on screen for 2+ seconds — this is the value prop |

**Total: 20 s.** Stays under the 30 s cap with margin. No QR/share, no prices, no end card.

If silent: deliver a 20 s MP4 with a silent AAC track (Apple wants the audio track present even if empty — drop a -inf dB track in the editor).

## 6. Editor checklist

Hand this to whoever edits — single-page checklist.

```
[ ] Project at 1080×1920 (App Preview) and 1920×1080 (YouTube) timelines
[ ] All clips imported from /raw/, organised by shot letter (A–K)
[ ] YouTube cut: 30.00 s exact (Play caps at 30 s; do not exceed)
[ ] App Preview cut: 20.00 s, no prices, no CTAs, no real-world B-roll
[ ] No Flutter debug banner visible in any frame
[ ] No system clock visible in any frame
[ ] No price callouts in App Preview cut (₹250, ₹50 etc.)
[ ] Music cleared & licensed (attach licence to delivery)
[ ] Captions are burned in, large, high contrast, NOT covering app UI
[ ] Final exports:
    - youtube-fotozen-30s-1080p.mp4 (H.264, AAC)
    - playstore-fotozen-30s-1080p-portrait.mp4 (if doing portrait Play cut)
    - appstore-fotozen-20s-iphone67-1290x2796.mp4 (silent ok)
    - appstore-fotozen-20s-iphone65-886x1920.mp4 (silent ok)
[ ] Test playback on a real iPhone before submission (Quick Look)
```

## 7. Storyboard — frame-by-frame for YouTube cut

Quick text mock so the editor sees the rhythm. Each box ≈ 2-3 s.

```
┌─────────┬─────────┬─────────┬─────────┬─────────┐
│ LOGO    │ THEMES  │ "Pick a │ CAMERA  │ FLASH ⚡ │
│ fade-in │ scroll  │ look"   │ framing │ capture │
├─────────┼─────────┼─────────┼─────────┼─────────┤
│ AI gen  │ HERO ★  │ HERO ★  │ QR share│ END CARD│
│ progress│ reveal  │ hold    │ scan    │ ₹250    │
└─────────┴─────────┴─────────┴─────────┴─────────┘
   2s        5s        7s        11s      14s
   17s       20s       22s       26s      30s
```

The two starred frames (HERO reveal + HERO hold) are the entire video. Everything else is build-up and aftermath.

## 8. What I can't do from here, what you'll need

| Task | Owner | Notes |
|---|---|---|
| Capture the screen recordings | Engineer with the iOS sim / Android emulator | Use commands in §3 |
| Edit the cuts | Videographer / in-house editor | Brief above is sufficient — no further direction needed |
| License music | Editor | ~$15/month Epidemic Sound covers both cuts |
| Voice-over (optional) | Skip for v1.0 | Adds days; on-screen text is faster |
| Localise | Skip for v1.0 | English-only is fine for India launch |

If you'd like, after the engineer does the screen captures, drop the raw clips into `release-bundle/assets/video-raw/` and I can produce a more specific edit decision list referencing actual timestamps in your footage.
