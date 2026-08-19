# Known issues

Open defects that are understood but not yet fixed. Each entry records the evidence,
the root cause, and what a fix would touch — so the next person does not re-derive it.

Last updated 2026-08-19.

---

## 1. The shared photo URL exposes every image in the session, not just the paid one

**Severity:** customer-facing privacy / correctness. A guest who pays for one photo
receives a link to *all* AI-generated images in their session, including ones they did
not buy and any regenerations they rejected.

### Evidence

The server decides scope from a single field:

```js
// zenai server/routes.ts — GET /s/:token and /share/:token
mode: link.imageIndex == null ? "album" : "single"
const isAlbum = link.imageIndex == null && allImages.length > 1;
description = isAlbum
  ? `View ${allImages.length} AI-generated photos from FotoZen.AI`
  : "Tap to view, save, or share your AI-generated photo from FotoZen.AI";
```

Both places that mint a link pass `null`:

```js
// zenai server/routes.ts — POST /api/sessions/:id/receipt
storage.createShareLink(session.accountId, id, RECEIPT_LINK_TTL_HOURS, null);
//                                                    imageIndex ────────^
```

```dart
// photobooth lib/screens/result/result_viewmodel_impl.part.dart:875
final kiosk = await mintCustomerShareLink();   // imageIndex omitted
```

So every link is album mode, and the share page's own preview text advertises
"View N AI-generated photos".

### Why an app-only fix will not work

The receipt's album `shareUrl` reaches the customer through **three** channels, not
just the on-screen QR:

```js
shareUrl → generateReceiptPdf({ ..., shareUrl })   // printed / stored receipt
shareUrl → whatsapp({ ..., photoUrl: shareUrl })   // customer's WhatsApp message
shareUrl → receiptShareUrl → the QR screen
```

and the QR screen *prefers* the receipt URL over the kiosk-minted one:

```dart
// lib/screens/qr_share/qr_share_copy_helpers.dart — resolveQrShareData
final shareUrl = (receiptShareUrl ?? parsedShareUrl ?? '').trim();
return shareUrl.isNotEmpty ? shareUrl : kioskUrl;
```

Changing only the app would leave WhatsApp and the receipt PDF still carrying the
album link.

### The single-image path already exists

The server calls it "Phase 2" and it is fully implemented:

> *when `link.imageIndex` is set, returns ONLY that image (rest of album hidden)*

and the app already threads an `imageIndex` parameter from `mintCustomerShareLink` →
`ApiService.createKioskShareLink` → the request body. **It is simply never given a
value.** This is a last-mile gap, not missing functionality.

### What a fix touches

Intended behaviour: **one share link per finalized-and-paid photo**, each scoped to that
photo. An AI upsell is a second paid photo and therefore gets its own link.

- **zenai** `server/routes.ts`, receipt endpoint: accept an image reference in the POST
  body and pass it to `createShareLink` instead of `null`.
- **photobooth** `lib/services/api_service.dart` + `result_viewmodel_impl.part.dart`:
  resolve the paid photo's 0-based index in `session.generatedImages` (the app mirrors
  that array in `SessionManager`, and `GeneratedImage.imageUrl` gives the match key),
  send it with `postSessionReceipt`, and pass the same index to
  `mintCustomerShareLink(imageIndex:)`.

**Open design question.** `photoUrl` (WhatsApp) and the receipt PDF each carry a *single*
URL, but `print_selection_viewmodel` allows selecting several images
(`selectedImages`, pricing is `selected images × copies`). If a multi-photo purchase in
one transaction is genuinely possible, it needs either N WhatsApp sends and N links on
the receipt, or a subset share mode on the server. Confirm which before implementing.

**Cleanup.** Album links already minted stay live until expiry.
`DELETE /api/kiosk/shares/:token?all=1` revokes them if past sessions need pulling.

### This is *not* specific to direct PTP

Checked 2026-08-19 after a report that EDSDK and Pi behaved differently: there is **no
camera-source branching anywhere** in `lib/screens/result/`, `lib/screens/qr_share/`, or
`lib/services/print_service.dart` — grep for `directPtp|cameraSource|usesDirectPtpCamera|sidecar`
returns nothing in those paths. The share flow is identical for EDSDK, Pi and direct PTP,
so the camera stack cannot change it.

If the flows *appeared* to differ, the likely explanation is how many entries landed in
`session.generatedImages` in each test — a session with one generation shows one photo in
album mode and looks correct, while a session with regenerations or upsells shows several.
That is worth confirming with a side-by-side repro, which was not possible on the current
rig: EDSDK cannot start on the arm64 phone (see issue 2) and Pi needs its hardware.

---

## 2. The EDSDK sidecar cannot start on arm64 — `direct` mode is unusable there

**Severity:** blocks `cameraConnectionMode=direct` on any arm64 Android device.

`photobooth/android/app/src/main/assets/canon_sidecar/arm64-v8a/` is missing three
libraries that `armeabi-v7a/` ships:

| file | armeabi-v7a | arm64-v8a |
|---|---|---|
| `libudev.so.1` | present | **missing** |
| `libatomic.so.1` | present | **missing** |
| `libusb_open_hook.so` | present | **missing** |

`libusb-1.0.so.0` links against `libudev.so.1`, so the binary never loads:

```
Starting canon-sidecar arm64-v8a (attempt 8) usbPermission=true usbFd=3
canon-sidecar exited with code 127 — restarting in 3 s
canon-sidecar exited with code 127 — max restarts reached
```

Nothing then listens on `127.0.0.1:8791`, the Flutter capture screen has no camera, and
the failure surfaces as "live view / capture not working" with no useful error — none of
which points at the sidecar.

`libusb_open_hook.so` is likely the shim that lets libusb adopt the pre-opened Android USB
fd (the spawn passes `usbFd=3`), so the bundle is incomplete rather than one file short.
Consistent with `CLAUDE.md` building the sidecar as `SIDECAR_ARCHES=arm32` for the 32-bit
Amlogic Mini PC.

**Diagnose** (exit 127 is a loader failure, so ask the loader):

```bash
adb shell 'run-as com.srisarani.fotozenai sh -c "cd /data/data/com.srisarani.fotozenai/files/canon_sidecar && LD_LIBRARY_PATH=. ./ld-linux-aarch64.so.1 --list ./canon-sidecar"'
```

Check the port with `adb shell cat /proc/net/tcp` and look for `:2257` (8791 in hex).

**Fix:** rebuild the payload for arm64 — `cd canon_sidecar && SIDECAR_ARCHES=arm64 ./build.sh`
(see `canon_sidecar/SETUP.md`) — and confirm all ten files land in the `arm64-v8a` asset
directory before shipping.

---

## 3. Print resolution is limited by AI generation size, not by the printer

**Severity:** print quality. Every print is upscaled before it reaches the printer.

### The printer

DNP DS-RX1HS supports **300×300 dpi** (high-speed) and **300×600 dpi** (high-resolution),
in glossy or matte, on 6"-wide media. Sizes: 3.5×5, 4×6, 5×5, 5×7, 6×6, 6×8, and 2×6
strips (2-up / 4-up). 4×6 in 12.4 s, ~290 prints/hour.
Sources: [DNP Europe](https://www.dnpphoto.eu/en/product-range/photo-printers/item/655-rx1hs),
[DNP US](https://dnpphoto.com/en-us/Products/Printers/ds-rx1hs),
[B&H](https://www.bhphotovideo.com/c/product/1264019-REG/dnp_ds_rx1hs_dye_sublimation_printer.html).
DNP does not publish raster pixel dimensions; those come from the driver.

### What we already send — this part is correct

`DnpPrintSize.kt` targets 300 dpi rasters, matching the open-source `dnpds40` CUPS backend:

| size | raster (w×h) | imageable |
|---|---|---|
| 4×6 | 1920 × 1240 | 1844 × 1240 |
| 5×7 | 1920 × 2138 | 1548 × 2138 |
| 6×8 | 1920 × 2436 | 1844 × 2436 |
| 2×6 | 1920 × 1240 | 1844 × 1240 |

`DnpImageProcessor.prepareBitmap` scales whatever it is given to these dimensions.

### The actual problem

The AI generator emits at most **1536×1024** (landscape), **1024×1536** (portrait) or
**1024×1024**:

```ts
// zenai server/lib/aiGenerator.ts
function resolveOpenAIImageSize(framing): "1024x1024" | "1024x1536" | "1536x1024"
```

There is no upscale before serving, and `result_viewmodel_impl.part.dart` prints the
downloaded generated file directly. So for a 4×6:

- printer raster: 1920 × 1240 = **2.38 MP**
- best available source: 1536 × 1024 = **1.57 MP**
- shortfall: **1.25× linear, 1.51× area** — an effective ~240 dpi rather than 300

**The "72 dpi" seen on the file is JFIF metadata, not the print resolution.** It is
cosmetic: the native path sizes by pixels, not by the density tag. The real loss is the
pixel shortfall above. Correcting the metadata alone would change nothing.

**Raising the DNP target to 300×600 would not help** while the source is 1536 px wide —
it would only upscale further. The binding constraint is generation size.

**Fix direction:** raise the generated image resolution (or add a quality upscale step) so
the source meets or exceeds 1920 px on the long edge before it reaches the print path.
Worth confirming what the current image model offers above 1536 px, and the cost per image.
