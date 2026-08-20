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

## 3. Print resolution — Classic is correct; only the AI path is suspect

**Status:** partially resolved by measurement 2026-08-19. The original entry claimed every
print was upscaled. That was wrong for the Classic path and is corrected below.

### The printer

DNP DS-RX1HS supports **300×300 dpi** (high-speed) and **300×600 dpi** (high-resolution),
glossy or matte, on 6"-wide media. Sizes: 3.5×5, 4×6, 5×5, 5×7, 6×6, 6×8 and 2×6 strips
(2-up / 4-up). 4×6 in 12.4 s, ~290 prints/hour.
Sources: [DNP Europe](https://www.dnpphoto.eu/en/product-range/photo-printers/item/655-rx1hs),
[DNP US](https://dnpphoto.com/en-us/Products/Printers/ds-rx1hs),
[B&H](https://www.bhphotovideo.com/c/product/1264019-REG/dnp_ds_rx1hs_dye_sublimation_printer.html).
DNP does not publish raster pixel dimensions; those come from the driver.

### Measured: what we actually send (Classic print, 2026-08-19)

The file handed to the print path was captured off the device mid-job, before
`file_helper_temp_cleanup` removed it:

```
transformed_70addbf8-6a2e-44de-b559-e99bd1ac2fac.jpg
1200 x 1800 px   2.16 MP   274 KB   JFIF density 72x72
```

**1200×1800 is exactly 4×6 at 300 dpi — correct.** Against the `DnpPrintSize.SIZE_4X6`
raster of 1920×1240, `DnpImageProcessor` rotates the portrait source and scales:

| axis | source (rotated) | raster | factor |
|---|---|---|---|
| long | 1800 | 1920 | 1.067× |
| short | 1200 | 1240 | 1.033× |

~6%, which is DNP's bleed margin. Normal and visually irrelevant.

### The 72 dpi tag is cosmetic — do not "fix" it

It is JFIF metadata. `DnpImageProcessor.prepareBitmap` sizes by pixel dimensions and never
reads the density tag, so rewriting it to 300 would change nothing on paper. The image is a
genuine 300 dpi 4×6.

### Still open: the AI path

Untested. The generator caps output at 1536×1024 / 1024×1536 / 1024×1024:

```ts
// zenai server/lib/aiGenerator.ts
function resolveOpenAIImageSize(framing): "1024x1024" | "1024x1536" | "1536x1024"
```

1024×1536 is *below* the 1200×1800 that a 4×6 needs, implying roughly a 17% upscale rather
than the Classic path's 6%. Whether that reaches the printer at 1024×1536 or is upscaled
server-side before serving has **not** been measured — do that before acting on it.

### How to measure this again

The print file lives only briefly. Watch for it on-device during a job:

```bash
adb shell "run-as com.srisarani.fotozenai sh -c 'D=/data/data/com.srisarani.fotozenai; mkdir -p \$D/files/_printcap; i=0; while [ \$i -lt 1200 ]; do for f in \$(find \$D/cache -maxdepth 2 -type f -name \"transformed_*\" 2>/dev/null); do b=\$(basename \$f); [ -e \$D/files/_printcap/\$b ] || cp \$f \$D/files/_printcap/\$b; done; i=\$((i+1)); sleep 1; done'"
```

Then pull with `adb exec-out run-as … cat` — **not** `adb shell cat`, which mangles binary.
A printer does not need to be connected: the download happens before the print attempt.

### Reference: strip pipeline caps

| stage | cap |
|---|---|
| Look-picker preview upload | ≤1600 long edge, q90 (`kStripPreviewGradeUploadMaxEdge`) |
| Classic strip look-bake → print | ≤2400 long edge, q92 (`kStripLookBakeMaxEdge`) |
