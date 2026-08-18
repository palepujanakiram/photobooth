# Device capabilities — Canon.Inc Canon EOS 200D II

Generated: 2026-08-17 11:17:14

> This file is **generated from the camera itself** and is authoritative.
> Where it disagrees with `ptp.h`, this file wins. Where `docs/PLAN.md`
> Appendix A or B disagrees with this file, **fix the plan**.

## Identity

| Field | Value |
|---|---|
| Manufacturer | Canon.Inc |
| Model | Canon EOS 200D II |
| Firmware | 3-1.0.1 |
| Serial | ffffffffffffffffffffffffffffffff |
| PTP standard version | 1.00 |
| Vendor extension | Microsoft |
| Vendor ext. version | 1.00 |
| Vendor ext. description | — |
| Functional mode | 0x0000 |

## Readiness checks

| Check | Result |
|---|---|
| **Implements EOS operation set** (the test that matters) | ✅ yes |
| Declares Canon vendor extension | ❌ **no** — *expected to be NO; EOS bodies report Microsoft* |
| JPEG capture supported (plan §2) | ✅ yes |
| EOS remote mode opcodes present (M3) | ✅ yes |
| `GetPartialObject` present (M4) | ✅ yes |

## Operations supported (175)

| Code | Name | Notes |
|---|---|---|
| `0x1001` | GetDeviceInfo |  |
| `0x1002` | OpenSession |  |
| `0x1003` | CloseSession |  |
| `0x1004` | GetStorageIDs |  |
| `0x1005` | GetStorageInfo |  |
| `0x1006` | GetNumObjects |  |
| `0x1007` | GetObjectHandles |  |
| `0x1008` | GetObjectInfo |  |
| `0x1009` | GetObject |  |
| `0x100A` | GetThumb |  |
| `0x100B` | DeleteObject |  |
| `0x100C` | Operation(0x100C) |  |
| `0x100D` | Operation(0x100D) |  |
| `0x100F` | Operation(0x100F) |  |
| `0x1014` | GetDevicePropDesc |  |
| `0x1016` | SetDevicePropValue |  |
| `0x101B` | GetPartialObject |  |
| `0x902F` | Operation(0x902F) | ⚠️ vendor opcode we do not have a name for |
| `0x9033` | Operation(0x9033) | ⚠️ vendor opcode we do not have a name for |
| `0x9050` | Operation(0x9050) | ⚠️ vendor opcode we do not have a name for |
| `0x9051` | Operation(0x9051) | ⚠️ vendor opcode we do not have a name for |
| `0x905C` | Operation(0x905C) | ⚠️ vendor opcode we do not have a name for |
| `0x905D` | Operation(0x905D) | ⚠️ vendor opcode we do not have a name for |
| `0x9060` | Operation(0x9060) | ⚠️ vendor opcode we do not have a name for |
| `0x9068` | Operation(0x9068) | ⚠️ vendor opcode we do not have a name for |
| `0x9069` | Operation(0x9069) | ⚠️ vendor opcode we do not have a name for |
| `0x906A` | Operation(0x906A) | ⚠️ vendor opcode we do not have a name for |
| `0x906B` | Operation(0x906B) | ⚠️ vendor opcode we do not have a name for |
| `0x906C` | Operation(0x906C) | ⚠️ vendor opcode we do not have a name for |
| `0x906D` | Operation(0x906D) | ⚠️ vendor opcode we do not have a name for |
| `0x906E` | Operation(0x906E) | ⚠️ vendor opcode we do not have a name for |
| `0x906F` | Operation(0x906F) | ⚠️ vendor opcode we do not have a name for |
| `0x9077` | Operation(0x9077) | ⚠️ vendor opcode we do not have a name for |
| `0x9078` | Operation(0x9078) | ⚠️ vendor opcode we do not have a name for |
| `0x9079` | Operation(0x9079) | ⚠️ vendor opcode we do not have a name for |
| `0x9101` | Operation(0x9101) | ⚠️ vendor opcode we do not have a name for |
| `0x9102` | Operation(0x9102) | ⚠️ vendor opcode we do not have a name for |
| `0x9103` | Operation(0x9103) | ⚠️ vendor opcode we do not have a name for |
| `0x9104` | Operation(0x9104) | ⚠️ vendor opcode we do not have a name for |
| `0x9105` | Operation(0x9105) | ⚠️ vendor opcode we do not have a name for |
| `0x9106` | Operation(0x9106) | ⚠️ vendor opcode we do not have a name for |
| `0x9107` | EOS_GetPartialObject | Canon vendor — **confirms our transcribed constant** |
| `0x9108` | Operation(0x9108) | ⚠️ vendor opcode we do not have a name for |
| `0x9109` | Operation(0x9109) | ⚠️ vendor opcode we do not have a name for |
| `0x910A` | Operation(0x910A) | ⚠️ vendor opcode we do not have a name for |
| `0x910C` | Operation(0x910C) | ⚠️ vendor opcode we do not have a name for |
| `0x910F` | EOS_RemoteRelease | Canon vendor — **confirms our transcribed constant** |
| `0x9110` | EOS_SetDevicePropValueEx | Canon vendor — **confirms our transcribed constant** |
| `0x9114` | EOS_SetRemoteMode | Canon vendor — **confirms our transcribed constant** |
| `0x9115` | EOS_SetEventMode | Canon vendor — **confirms our transcribed constant** |
| `0x9116` | EOS_GetEvent | Canon vendor — **confirms our transcribed constant** |
| `0x9117` | EOS_TransferComplete | Canon vendor — **confirms our transcribed constant** |
| `0x9118` | EOS_CancelTransfer | Canon vendor — **confirms our transcribed constant** |
| `0x911A` | EOS_PCHDDCapacity | Canon vendor — **confirms our transcribed constant** |
| `0x911B` | EOS_SetUILock | Canon vendor — **confirms our transcribed constant** |
| `0x911C` | EOS_ResetUILock | Canon vendor — **confirms our transcribed constant** |
| `0x911D` | EOS_KeepDeviceOn | Canon vendor — **confirms our transcribed constant** |
| `0x911E` | EOS_SetNullPacketMode | Canon vendor — **confirms our transcribed constant** |
| `0x911F` | Operation(0x911F) | ⚠️ vendor opcode we do not have a name for |
| `0x9122` | Operation(0x9122) | ⚠️ vendor opcode we do not have a name for |
| `0x9123` | Operation(0x9123) | ⚠️ vendor opcode we do not have a name for |
| `0x9124` | Operation(0x9124) | ⚠️ vendor opcode we do not have a name for |
| `0x9127` | Operation(0x9127) | ⚠️ vendor opcode we do not have a name for |
| `0x9128` | EOS_RemoteReleaseOn | Canon vendor — **confirms our transcribed constant** |
| `0x9129` | EOS_RemoteReleaseOff | Canon vendor — **confirms our transcribed constant** |
| `0x912B` | Operation(0x912B) | ⚠️ vendor opcode we do not have a name for |
| `0x912C` | Operation(0x912C) | ⚠️ vendor opcode we do not have a name for |
| `0x912D` | Operation(0x912D) | ⚠️ vendor opcode we do not have a name for |
| `0x912E` | Operation(0x912E) | ⚠️ vendor opcode we do not have a name for |
| `0x912F` | Operation(0x912F) | ⚠️ vendor opcode we do not have a name for |
| `0x9130` | Operation(0x9130) | ⚠️ vendor opcode we do not have a name for |
| `0x9131` | Operation(0x9131) | ⚠️ vendor opcode we do not have a name for |
| `0x9132` | Operation(0x9132) | ⚠️ vendor opcode we do not have a name for |
| `0x9133` | Operation(0x9133) | ⚠️ vendor opcode we do not have a name for |
| `0x9134` | Operation(0x9134) | ⚠️ vendor opcode we do not have a name for |
| `0x9135` | Operation(0x9135) | ⚠️ vendor opcode we do not have a name for |
| `0x9136` | Operation(0x9136) | ⚠️ vendor opcode we do not have a name for |
| `0x9137` | Operation(0x9137) | ⚠️ vendor opcode we do not have a name for |
| `0x9138` | Operation(0x9138) | ⚠️ vendor opcode we do not have a name for |
| `0x9139` | Operation(0x9139) | ⚠️ vendor opcode we do not have a name for |
| `0x913A` | Operation(0x913A) | ⚠️ vendor opcode we do not have a name for |
| `0x913B` | Operation(0x913B) | ⚠️ vendor opcode we do not have a name for |
| `0x913C` | Operation(0x913C) | ⚠️ vendor opcode we do not have a name for |
| `0x913D` | Operation(0x913D) | ⚠️ vendor opcode we do not have a name for |
| `0x913E` | Operation(0x913E) | ⚠️ vendor opcode we do not have a name for |
| `0x913F` | Operation(0x913F) | ⚠️ vendor opcode we do not have a name for |
| `0x9140` | Operation(0x9140) | ⚠️ vendor opcode we do not have a name for |
| `0x9141` | Operation(0x9141) | ⚠️ vendor opcode we do not have a name for |
| `0x9143` | Operation(0x9143) | ⚠️ vendor opcode we do not have a name for |
| `0x9144` | Operation(0x9144) | ⚠️ vendor opcode we do not have a name for |
| `0x9145` | Operation(0x9145) | ⚠️ vendor opcode we do not have a name for |
| `0x9146` | Operation(0x9146) | ⚠️ vendor opcode we do not have a name for |
| `0x9147` | Operation(0x9147) | ⚠️ vendor opcode we do not have a name for |
| `0x9148` | Operation(0x9148) | ⚠️ vendor opcode we do not have a name for |
| `0x9149` | Operation(0x9149) | ⚠️ vendor opcode we do not have a name for |
| `0x914A` | Operation(0x914A) | ⚠️ vendor opcode we do not have a name for |
| `0x914B` | Operation(0x914B) | ⚠️ vendor opcode we do not have a name for |
| `0x914C` | Operation(0x914C) | ⚠️ vendor opcode we do not have a name for |
| `0x914D` | Operation(0x914D) | ⚠️ vendor opcode we do not have a name for |
| `0x914E` | Operation(0x914E) | ⚠️ vendor opcode we do not have a name for |
| `0x914F` | Operation(0x914F) | ⚠️ vendor opcode we do not have a name for |
| `0x9150` | Operation(0x9150) | ⚠️ vendor opcode we do not have a name for |
| `0x9153` | EOS_GetViewFinderData | Canon vendor — **confirms our transcribed constant** |
| `0x9154` | EOS_DoAf | Canon vendor — **confirms our transcribed constant** |
| `0x9155` | EOS_DriveLens | Canon vendor — **confirms our transcribed constant** |
| `0x9157` | Operation(0x9157) | ⚠️ vendor opcode we do not have a name for |
| `0x9158` | EOS_Zoom | Canon vendor — **confirms our transcribed constant** |
| `0x9159` | EOS_ZoomPosition | Canon vendor — **confirms our transcribed constant** |
| `0x915A` | EOS_SetLiveAfFrame | Canon vendor — **confirms our transcribed constant** |
| `0x915B` | Operation(0x915B) | ⚠️ vendor opcode we do not have a name for |
| `0x915C` | Operation(0x915C) | ⚠️ vendor opcode we do not have a name for |
| `0x915D` | Operation(0x915D) | ⚠️ vendor opcode we do not have a name for |
| `0x9160` | EOS_AfCancel | Canon vendor — **confirms our transcribed constant** |
| `0x916B` | Operation(0x916B) | ⚠️ vendor opcode we do not have a name for |
| `0x916C` | Operation(0x916C) | ⚠️ vendor opcode we do not have a name for |
| `0x916D` | Operation(0x916D) | ⚠️ vendor opcode we do not have a name for |
| `0x916E` | Operation(0x916E) | ⚠️ vendor opcode we do not have a name for |
| `0x916F` | Operation(0x916F) | ⚠️ vendor opcode we do not have a name for |
| `0x9170` | Operation(0x9170) | ⚠️ vendor opcode we do not have a name for |
| `0x9171` | Operation(0x9171) | ⚠️ vendor opcode we do not have a name for |
| `0x9172` | Operation(0x9172) | ⚠️ vendor opcode we do not have a name for |
| `0x9173` | Operation(0x9173) | ⚠️ vendor opcode we do not have a name for |
| `0x9174` | Operation(0x9174) | ⚠️ vendor opcode we do not have a name for |
| `0x9177` | Operation(0x9177) | ⚠️ vendor opcode we do not have a name for |
| `0x9178` | Operation(0x9178) | ⚠️ vendor opcode we do not have a name for |
| `0x9179` | Operation(0x9179) | ⚠️ vendor opcode we do not have a name for |
| `0x9180` | Operation(0x9180) | ⚠️ vendor opcode we do not have a name for |
| `0x9181` | Operation(0x9181) | ⚠️ vendor opcode we do not have a name for |
| `0x9182` | Operation(0x9182) | ⚠️ vendor opcode we do not have a name for |
| `0x9183` | Operation(0x9183) | ⚠️ vendor opcode we do not have a name for |
| `0x9184` | Operation(0x9184) | ⚠️ vendor opcode we do not have a name for |
| `0x9185` | Operation(0x9185) | ⚠️ vendor opcode we do not have a name for |
| `0x91AE` | Operation(0x91AE) | ⚠️ vendor opcode we do not have a name for |
| `0x91AF` | Operation(0x91AF) | ⚠️ vendor opcode we do not have a name for |
| `0x91B9` | Operation(0x91B9) | ⚠️ vendor opcode we do not have a name for |
| `0x91D3` | Operation(0x91D3) | ⚠️ vendor opcode we do not have a name for |
| `0x91D4` | Operation(0x91D4) | ⚠️ vendor opcode we do not have a name for |
| `0x91D5` | Operation(0x91D5) | ⚠️ vendor opcode we do not have a name for |
| `0x91D7` | Operation(0x91D7) | ⚠️ vendor opcode we do not have a name for |
| `0x91D8` | Operation(0x91D8) | ⚠️ vendor opcode we do not have a name for |
| `0x91D9` | Operation(0x91D9) | ⚠️ vendor opcode we do not have a name for |
| `0x91DA` | Operation(0x91DA) | ⚠️ vendor opcode we do not have a name for |
| `0x91DB` | Operation(0x91DB) | ⚠️ vendor opcode we do not have a name for |
| `0x91DC` | Operation(0x91DC) | ⚠️ vendor opcode we do not have a name for |
| `0x91DD` | Operation(0x91DD) | ⚠️ vendor opcode we do not have a name for |
| `0x91DE` | Operation(0x91DE) | ⚠️ vendor opcode we do not have a name for |
| `0x91DF` | Operation(0x91DF) | ⚠️ vendor opcode we do not have a name for |
| `0x91E1` | Operation(0x91E1) | ⚠️ vendor opcode we do not have a name for |
| `0x91E2` | Operation(0x91E2) | ⚠️ vendor opcode we do not have a name for |
| `0x91E3` | Operation(0x91E3) | ⚠️ vendor opcode we do not have a name for |
| `0x91E4` | Operation(0x91E4) | ⚠️ vendor opcode we do not have a name for |
| `0x91E6` | Operation(0x91E6) | ⚠️ vendor opcode we do not have a name for |
| `0x91E7` | Operation(0x91E7) | ⚠️ vendor opcode we do not have a name for |
| `0x91E8` | Operation(0x91E8) | ⚠️ vendor opcode we do not have a name for |
| `0x91E9` | Operation(0x91E9) | ⚠️ vendor opcode we do not have a name for |
| `0x91EA` | Operation(0x91EA) | ⚠️ vendor opcode we do not have a name for |
| `0x91EB` | Operation(0x91EB) | ⚠️ vendor opcode we do not have a name for |
| `0x91EC` | Operation(0x91EC) | ⚠️ vendor opcode we do not have a name for |
| `0x91ED` | Operation(0x91ED) | ⚠️ vendor opcode we do not have a name for |
| `0x91EE` | Operation(0x91EE) | ⚠️ vendor opcode we do not have a name for |
| `0x91EF` | Operation(0x91EF) | ⚠️ vendor opcode we do not have a name for |
| `0x91F0` | Operation(0x91F0) | ⚠️ vendor opcode we do not have a name for |
| `0x91F1` | Operation(0x91F1) | ⚠️ vendor opcode we do not have a name for |
| `0x91F2` | Operation(0x91F2) | ⚠️ vendor opcode we do not have a name for |
| `0x91F3` | Operation(0x91F3) | ⚠️ vendor opcode we do not have a name for |
| `0x91F4` | Operation(0x91F4) | ⚠️ vendor opcode we do not have a name for |
| `0x91F5` | Operation(0x91F5) | ⚠️ vendor opcode we do not have a name for |
| `0x91F6` | Operation(0x91F6) | ⚠️ vendor opcode we do not have a name for |
| `0x91F8` | Operation(0x91F8) | ⚠️ vendor opcode we do not have a name for |
| `0x91F9` | Operation(0x91F9) | ⚠️ vendor opcode we do not have a name for |
| `0x91FB` | Operation(0x91FB) | ⚠️ vendor opcode we do not have a name for |
| `0x91FC` | Operation(0x91FC) | ⚠️ vendor opcode we do not have a name for |
| `0x91FD` | Operation(0x91FD) | ⚠️ vendor opcode we do not have a name for |
| `0x91FE` | Operation(0x91FE) | ⚠️ vendor opcode we do not have a name for |
| `0x91FF` | Operation(0x91FF) | ⚠️ vendor opcode we do not have a name for |

### Transcribed Canon opcodes NOT reported by this body

These are in `CanonEosOperation` but this camera does not list them.
Either the constant is wrong (check `ptp.h`) or the body genuinely lacks it.
**Record each one in `GAPS_AND_EDGE_CASES.md` before relying on it.**

- `0x9113` EOS_GetRemoteMode
- `0x9119` EOS_ResetTransfer
- `0x9125` EOS_BulbStart
- `0x9126` EOS_BulbEnd

## Device properties supported (5)

> ⚠️ **This list is NOT the EOS control surface.** Verified on hardware
> 2026-08-13: an EOS 200D II reports only ~5 standard properties here, while
> emitting `PropValueChanged` events for dozens of `0xD1xx` EOS properties.
> **EOS properties are discoverable only through the event stream**, not through
> `GetDeviceInfo`. M7 must build its control surface from observed events plus
> `EOS_SetDevicePropValueEx`, not from this list.

| Code |
|---|
| `0x5001` |
| `0xD303` |
| `0xD402` |
| `0xD406` |
| `0xD407` |

## Events supported (19)

- `0x4003`
- `0x4009`
- `0xC181`
- `0xC183`
- `0xC184`
- `0xC185`
- `0xC186`
- `0xC187`
- `0xC188`
- `0xC189`
- `0xC18A`
- `0xC18B`
- `0xC18D`
- `0xC18E`
- `0xC18F`
- `0xC190`
- `0xC191`
- `0xC1A0`
- `0xC1A1`

## Capture formats (1)

- `0x3801` EXIF/JPEG

## Image formats (12)

- `0x3001` Association
- `0x3002` Format(0x3002)
- `0x3006` Format(0x3006)
- `0x300A` Format(0x300A)
- `0x3008` Format(0x3008)
- `0x3801` EXIF/JPEG
- `0xB101` Format(0xB101)
- `0xB103` Format(0xB103)
- `0xBF02` Format(0xBF02)
- `0x3800` Format(0x3800)
- `0xB104` Format(0xB104)
- `0xB105` Format(0xB105)

