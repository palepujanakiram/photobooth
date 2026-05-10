# Store Listing Copy

Drop these straight into the Play Console and App Store Connect listing forms.

## App name

| Field | Value | Notes |
|---|---|---|
| App name (Play Console) | **FotoZen AI** | Max 30 chars. Currently 10. |
| App name (App Store Connect) | **FotoZen AI** | Max 30 chars. |
| Subtitle (App Store only, max 30 chars) | **AI Photo Booth Kiosk** | |

> ⚠️ The iOS `Info.plist` currently has `CFBundleDisplayName = "Photo Booth"`. Update to **`FotoZen AI`** before archiving for App Store Connect — otherwise the name on the device home screen won't match the listing.

## Short / promotional descriptions

**Play Console — Short description (max 80 chars):**

> Capture, transform, print — AI-styled portraits in 60 seconds at any FotoZen kiosk.

**Play Console — Promo text / App Store promotional text (max 170 chars):**

> FotoZen AI turns a single photo into a stunning AI-styled portrait — and prints it on premium 4×6 paper at our kiosks across India. 50+ themes, instant UPI checkout.

## Full description

**Play Console / App Store full description** (under both stores' character limits — Play 4 000, App Store 4 000):

```
FotoZen AI is the operator app for FotoZen.AI photo-booth kiosks deployed at malls,
events, and venues across India. Capture or upload a photo, choose from 50+ AI
transformation themes, and walk away with a premium 4×6 print in under 60 seconds.

WHAT IT DOES
• Live camera capture with adjustable framing
• 50+ AI styles powered by state-of-the-art image generation
• On-screen preview before payment — you see exactly what prints
• Secure UPI payment via Cashfree (GPay, PhonePe, Paytm and more)
• Instant 4K printing on premium 4×6 photo paper
• Optional digital copy via QR or WhatsApp share
• 1 free regeneration included if the first AI result isn't perfect

PRICING
• ₹250 — full session (capture, AI styling, 4×6 print, 1 free regen)
• ₹50  — additional regeneration
• ₹50  — extra print of the same image

PRIVACY-FIRST
• Photos are processed only to generate your print and digital copy
• Images are deleted automatically within 15 minutes of printing
• Your photos are never used to train AI models, never sold, never shared

WHERE TO FIND US
FotoZen AI kiosks are operated by Srisarani Ventures Pvt Ltd at events,
shopping centres and venues across India. Visit https://www.srisarani.com
for partnerships and event bookings.

SUPPORT
support@fotozenai.com — replies within one business day.
```

## Category

| Store | Primary category | Secondary |
|---|---|---|
| Play Console | **Photography** | Entertainment |
| App Store Connect | **Photo & Video** | Entertainment |

## Content rating / age

- **Play Console IARC questionnaire**: select Photography → no violence, no sexual content, no controlled-substance references, no user-generated content visible to other users. Expected rating: **3+ / Everyone**.
- **App Store age rating**: **4+** (no objectionable content). Note: the app does collect facial images, but does not display third-party UGC.

## Tags / keywords

**App Store Connect "Keywords" (max 100 chars, comma-separated, no spaces after commas):**

```
ai photo,photo booth,kiosk,portrait,ai art,selfie,printing,fotozen,photo print,event
```

**Play Console** doesn't use a keyword field — relies on the description; the long description above already contains the relevant terms.

## Listing URLs (already live)

| Field | URL |
|---|---|
| App website | https://www.srisarani.com |
| Privacy policy | https://fotozenai.fly.dev/privacy |
| Terms & Conditions (App Store EULA URL) | https://fotozenai.fly.dev/terms |
| Marketing landing | https://www.srisarani.com |

## Support contact

| Field | Value |
|---|---|
| Support email | support@fotozenai.com |
| Support URL | https://fotozenai.fly.dev/contact |
| Phone (App Store requires for paid apps; not required here) | leave blank |

## Distribution

- **Countries:** India only for v1.0. Expand later once the kiosk rollout grows.
- **Pricing:** Free.
- **In-app purchases:** None on Android. iOS — see `03-app-privacy-ios.md` for the IAP-vs-physical-good decision; recommended setting for v1.0 is **No in-app purchases** (payment is for a physical print, processed offline via UPI/Cashfree, which is allowed under Apple's "physical goods/services" guideline 3.1.5).
