# App Store Connect — App Privacy form answers

The App Privacy questionnaire in App Store Connect is structured around **data types** and, for each, asks whether you collect it, link it to user identity, and use it for tracking. Answers below match the live privacy policy at https://fotozenai.fly.dev/privacy.

## Top-level questions

| Question | Answer |
|---|---|
| Does this app collect any data? | **Yes** |
| Does this app use third-party SDKs that collect data? | **Yes** (Cashfree, Bugsnag, Firebase Messaging) |

## Data type declarations

For each row: **Collected = Yes/No**, **Linked to user = Yes/No**, **Used for tracking = Yes/No**, **Purpose**.

| Data type | Collected | Linked to user | Tracking | Purpose(s) |
|---|---|---|---|---|
| Contact info → Email address | ✅ | ❌ Not linked (transient session-scoped) | ❌ | App Functionality |
| Contact info → Phone number | ✅ | ❌ Not linked | ❌ | App Functionality |
| Contact info → Name, physical address | ❌ | — | — | — |
| Health & fitness | ❌ | — | — | — |
| Financial info → Payment info | ✅ | ❌ Not linked (handled by Cashfree; we get metadata only) | ❌ | App Functionality, Fraud Prevention |
| Financial info → Purchase history | ✅ | ❌ Not linked | ❌ | App Functionality, Analytics |
| Financial info → Credit, other | ❌ | — | — | — |
| Location → Precise / coarse | ❌ | — | — | — |
| Sensitive info | ❌ | — | — | — |
| Contacts | ❌ | — | — | — |
| User content → Photos or videos | ✅ | ❌ Not linked (auto-deleted ≤15 min) | ❌ | App Functionality |
| User content → Audio | ❌ | — | — | — |
| User content → Customer support | ✅ (only if a user emails support) | ❌ | ❌ | App Functionality |
| User content → Other | ❌ | — | — | — |
| Browsing history | ❌ | — | — | — |
| Search history | ❌ | — | — | — |
| Identifiers → User ID | ❌ | — | — | — |
| Identifiers → Device ID | ✅ (internal kiosk binding ID) | ❌ | ❌ | App Functionality |
| Usage data → Product interaction | ✅ | ❌ | ❌ | Analytics, App Functionality |
| Usage data → Advertising data, other | ❌ | — | — | — |
| Diagnostics → Crash data | ✅ | ❌ | ❌ | App Functionality |
| Diagnostics → Performance data | ✅ | ❌ | ❌ | App Functionality |
| Diagnostics → Other diagnostic data | ❌ | — | — | — |

> "Linked to user" is **No** across the board because the app does not maintain user accounts — sessions are anonymous, payment metadata is not tied to a persistent identity, and photos are deleted within 15 minutes of printing.

## Tracking declaration

**Does this app track users?** → **No.**

This means **no `NSUserTrackingUsageDescription`** key needs to be added to `Info.plist`, and the App Tracking Transparency prompt is not required.

## App Privacy Details — short copy per data type

Free-text justification for the form:

- **Photos:** *"User photos captured at the kiosk, transformed by AI, and printed. Auto-deleted within 15 minutes of printing."*
- **Email / phone (optional):** *"Collected only when the user requests a digital copy of their photo via QR / WhatsApp / email."*
- **Payment info:** *"Transaction metadata returned by our payment processor (Cashfree Payments). Card and UPI details are handled by Cashfree's PCI-DSS-compliant flow and never reach our servers."*
- **Diagnostics & usage data:** *"Aggregate, anonymised analytics on session flow and Bugsnag crash reports."*
- **Device ID:** *"Internal kiosk binding identifier; links the app installation to a specific kiosk for printer routing. Not the IDFA / advertising identifier."*

## Apple-specific compliance toggles

| Field | Value | Source |
|---|---|---|
| Export Compliance — Uses non-exempt encryption? | **No** | Standard HTTPS only; no custom crypto. Add `ITSAppUsesNonExemptEncryption = false` to `Info.plist`. |
| Content Rights | **Yes — contains, displays, or accesses third-party content** | AI-generated images are derived from user-submitted input |
| Advertising Identifier (IDFA) | **No** | Not used |
| In-App Purchase | **No** | Print is a physical good processed offline via UPI — falls under guideline 3.1.5 (physical goods/services) |

## Reviewer notes (App Review submission)

Provide this in the **App Review Information → Notes** field at submission time:

```
FotoZen AI is the operator app for AI-powered photo-booth kiosks deployed at
malls and events across India. The app is intended to run on tablets paired
with USB cameras and a thermal photo printer.

Reviewer flow without kiosk hardware:
1. Open the app — you'll see a kiosk binding screen.
2. Use kiosk code: <REVIEWER_CODE_TBD>  (request from support@fotozenai.com).
3. The flow proceeds with the device's front camera in lieu of an external camera.
4. Choose any AI theme. AI generation runs against our test endpoint and returns
   a watermarked sample image (no payment required).
5. Tap "Print" — in reviewer mode the app shows a confirmation screen instead
   of triggering an actual print.

Payment: For end users, payment is collected for a physical 4×6 photo print
delivered immediately at the kiosk. This is a physical good and is processed
via UPI through Cashfree Payments — Apple guideline 3.1.5(a) explicitly permits
this and does not require IAP.

Permissions:
- Camera: required to capture the user's photo.
- Microphone: needed only for external (USB) camera initialisation; on a
  reviewer device with the front camera, the prompt may still appear due to
  AVFoundation — feel free to deny it, the app remains functional.
- Photo Library: optional, used only if the user chooses to save a copy.
- Notifications: operational notifications to kiosk operators (low-priority).

Contact: support@fotozenai.com
```

> Engineer action: generate a reviewer kiosk code that points to a test endpoint with no live printer or live payment, then paste it into the notes above before submission.
