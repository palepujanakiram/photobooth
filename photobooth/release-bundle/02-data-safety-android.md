# Play Console — Data safety form answers

Sourced from the live privacy policy at https://fotozenai.fly.dev/privacy and the actual code paths in `lib/`.

The Play Console "Data safety" form is broken into sections — answer each as below.

## Does your app collect or share any of the required user data types?

**Yes — it collects, and shares with a payment processor.**

## Is all of the user data collected by your app encrypted in transit?

**Yes.** All API traffic between the app and `fotozenai.fly.dev` is over HTTPS / TLS.

> Engineer note: the `AndroidManifest.xml` currently has `android:usesCleartextTraffic="true"`. Set this to `false` for the production build, or restrict via a `network-security-config.xml` whitelist, before submitting — Play reviewers are increasingly flagging cleartext-permitting apps.

## Do you provide a way for users to request that their data be deleted?

**Yes — in-app and via email.** Users can request immediate deletion at any time during the kiosk session, or email support@fotozenai.com. Photos are also auto-deleted within 15 minutes of printing.

## Data types — declare each as "collected" / "shared" / "neither"

| Category | Data type | Collected? | Shared? | Optional? | Purpose | Notes |
|---|---|---|---|---|---|---|
| **Personal info** | Email address | ✅ Yes | ❌ No | ✅ Optional | App functionality (digital copy delivery) | Only if user enters it for QR/email delivery |
| **Personal info** | Phone number | ✅ Yes | ❌ No | ✅ Optional | App functionality (WhatsApp/SMS delivery) | Only if user enters it |
| **Personal info** | Name | ❌ No | — | — | — | Not collected |
| **Personal info** | User IDs | ❌ No | — | — | — | Not collected |
| **Personal info** | Address | ❌ No | — | — | — | Not collected |
| **Financial info** | User payment info | ✅ Yes (metadata only) | ✅ Yes | ❌ Required | App functionality, fraud prevention | Cashfree handles card/UPI; we receive only transaction ID + amount + timestamp |
| **Financial info** | Purchase history | ✅ Yes | ❌ No | ❌ Required | App functionality, analytics | Tied to kiosk session, not to a long-lived user account |
| **Financial info** | Credit score, other financial info | ❌ No | — | — | — | Not collected |
| **Health & fitness** | — | ❌ No | — | — | — | — |
| **Messages** | — | ❌ No | — | — | — | — |
| **Photos and videos** | Photos | ✅ Yes | ❌ No (processed via our own servers) | ❌ Required | App functionality (AI generation, printing) | Auto-deleted ≤15 min after print |
| **Photos and videos** | Videos | ❌ No | — | — | — | — |
| **Audio files** | — | ❌ No | — | — | — | — |
| **Files and docs** | — | ❌ No | — | — | — | — |
| **Calendar** | — | ❌ No | — | — | — | — |
| **Contacts** | — | ❌ No | — | — | — | — |
| **App activity** | App interactions | ✅ Yes | ❌ No | ❌ Required | Analytics, app functionality | Aggregate, anonymised |
| **App activity** | In-app search history | ❌ No | — | — | — | — |
| **App activity** | Other user-generated content | ❌ No | — | — | — | — |
| **Web browsing** | — | ❌ No | — | — | — | — |
| **App info & performance** | Crash logs | ✅ Yes | ✅ Yes (Firebase Crashlytics) | ❌ Required | Analytics, app functionality | Standard Firebase Crashlytics; no PII |
| **App info & performance** | Diagnostics | ✅ Yes | ✅ Yes (Firebase) | ❌ Required | Analytics | Performance metrics |
| **App info & performance** | Other app performance data | ❌ No | — | — | — | — |
| **Device or other IDs** | Device or other IDs | ✅ Yes (kiosk binding only) | ❌ No | ❌ Required | App functionality (link to a kiosk) | Internal kiosk identifier — not advertising ID |

## Security practices section

- **Data is encrypted in transit:** Yes (HTTPS/TLS).
- **Users can request data deletion:** Yes (in-app + email).
- **Committed to Play Families Policy:** Not required (not directed at children).
- **Independent security review:** No (small team; not yet conducted).

## Third parties / data shared

| Third party | Data shared | Purpose |
|---|---|---|
| **Cashfree Payments** | Transaction metadata, payment instrument type | Payment processing |
| **Google (Firebase Crashlytics)** | Crash logs, device model, OS version | Crash reporting |
| **Google (Firebase Cloud Messaging)** | FCM token (notification only) | Operational notifications to kiosk |
| **Supabase / Google Cloud** | Photos, generated images (auto-deleted ≤15 min after print) | Storage during the live session |

## "Why is this data collected?" — recommended copy per data type

Use these directly in the form's free-text explanation field:

- **Photos:** *"To generate the AI-styled portrait the user pays for, and to drive the kiosk printer. Auto-deleted within 15 minutes of printing."*
- **Email / phone (optional):** *"Only if the user opts to receive a digital copy of their photo via QR / email / WhatsApp."*
- **Payment info:** *"Transaction metadata received from our PCI-DSS-compliant payment processor (Cashfree). Used to confirm payment, prevent fraud, and process refunds."*
- **App interactions / diagnostics:** *"Aggregate, anonymised analytics on session flow and crash diagnostics, used solely to improve reliability."*
- **Device IDs:** *"Internal kiosk binding — links the app instance to a specific kiosk for operations and printing. Not the Android Advertising ID."*

## Sensitive permissions / use-case declarations

The app does **not** request any of the following Play "sensitive" permissions, so no extra declaration is needed:

- `READ_SMS` / `RECEIVE_SMS` — not used.
- `QUERY_ALL_PACKAGES` — not used.
- `MANAGE_EXTERNAL_STORAGE` — not used.
- `REQUEST_INSTALL_PACKAGES` — not used.
- `ACCESS_BACKGROUND_LOCATION` — not used.

## Target audience

- **Primary audience:** 18+ (operator-facing kiosk app; consumers interact with the kiosk under operator supervision).
- **Children directed?** No.
