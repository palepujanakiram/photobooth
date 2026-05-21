# Developer Account Info

Use these values when configuring the **Google Play Console** publisher profile and the **App Store Connect** organisation profile.

## Legal entity

| Field | Value |
|---|---|
| Legal entity name | **Srisarani Ventures Private Limited** |
| Trading name (optional) | FotoZen.AI |
| Country of incorporation | India |
| Website | https://www.srisarani.com |
| Product domain | https://fotozenai.fly.dev (production server, also hosts public legal pages) |

## Registered office (sourced from `/contact` page on production)

```
Srisarani Ventures Private Limited
Plot No 5 to 9, A301, Capitalgreen Apartments
Secretariat Colony, Puppalaguda, Rajendranagar
Hyderabad, Telangana, India - 500089
```

> Use the registered-office address verbatim for both:
> - Play Console "Developer contact" → Physical address (required for Play distribution and visible to users)
> - App Store Connect "Legal Entity" + "Trade Representative Information" (also visible to users in EU)

## Public-facing contact

| Channel | Value |
|---|---|
| Support email | support@fotozenai.com |
| Support URL | https://fotozenai.fly.dev/contact |
| Marketing URL | https://www.srisarani.com |
| Privacy policy URL | https://fotozenai.fly.dev/privacy |
| Business hours | Monday – Saturday, 10:00 – 19:00 IST |

## Items the deployment engineer needs from Raghav

These cannot be answered from the repo and need confirmation:

| Field | Why it's needed | Where to fill |
|---|---|---|
| **Apple Developer Program account** — organisation enrolment number / D-U-N-S | App Store Connect requires a DUNS-verified company account | App Store Connect "Membership" |
| **Google Play Console developer account** — payment profile | Required even for free apps | Play Console settings |
| **GST registration number** (GSTIN) | Required by Apple for India-incorporated developers; Play uses it for tax setup | Both consoles |
| **PAN of the entity** | India tax compliance | Both consoles |
| **Authorised signatory name + designation** | App Store Connect agreements | App Store Connect "Agreements, Tax, and Banking" |
| **Bank account for payouts** (only relevant if app becomes paid in future) | — | Both consoles |
| **Designated reviewer contact at Srisarani** — name + phone | App Review may call for a signed-in demo | App Store Connect "App Review Information" |

## What the deployment engineer should NOT do without explicit confirmation

- Do not accept App Store Connect's "Paid Applications Agreement" — only the free agreement is needed for v1.0.
- Do not enable "Sign in with Apple" — there is no user account system in the app.
- Do not enable "Family Sharing" — kiosk app, not relevant.
- Do not opt the app into Play's "Advertising ID" usage — the app does not use IDFA / GAID.
- Do not connect any analytics SDK beyond what's already in the build (Bugsnag + FCM). Adding GA4 / Adjust / etc. would change the Data Safety / App Privacy answers in this bundle.
