# TODO

## Features

### Preferred IP + Interface override for network outputs

- [x] Art-Net and OSC daemons accept `--src-ip` (binds sending socket to a local IPv4)
- [x] Split interface enumeration into `reatc_netdiscover.py` (single responsibility)
- [x] Windows enumeration via ctypes `GetAdaptersAddresses` — locale-independent (no `ipconfig` parsing)
- [x] Accept comma-separated destination list in Art-Net daemon for multi-unicast
- [x] `is_valid_cidr` / `cidr_match` / `resolve_bind_ip` helpers in core.lua
- [x] Wire Preferred IP (CIDR) + Interface override + "Bound to:" status into Art-Net and OSC settings UI
- [x] Persist `*_preferred_ip` and `*_preferred_iface` via `ExtState`

**Context:** Multi-NIC hosts previously sent Art-Net out whatever NIC the OS default route picked — wrong when the lighting network is on a secondary interface. The Preferred IP CIDR is portable across machines (`10.0.0.0/8` means the same everywhere); the Interface combo is the explicit escape hatch for cases where two NICs share overlapping ranges but route to different networks. Resolution order: explicit Interface → CIDR match → Auto/default route.

## Bugs

### "ReaTC: failed to register custom action" on ReaPack install

- [x] Investigate and fix custom action registration failure on ReaPack installs

**Symptom:** `ReaTC: failed to register custom action` appears in REAPER console when the extension is installed via ReaPack. Local install (`make install`) works fine.

**Root cause (likely):** Dual installation conflict. If both a local install (`reaper_reatc.dylib`) and a ReaPack install (`reaper_reatc-arm64.dylib`) exist in `UserPlugins/`, REAPER loads both. The second one fails because the action IDs (`_REATC_MAIN`, etc.) are already registered by the first. The extension returns 0 (fatal) on any registration failure (`reaper_reatc.cpp:325-330`).

**Files:**
- `src/extension/reaper_reatc.cpp` lines 325-330 — registration loop, returns 0 on failure

**Possible fixes:**
1. Make the error non-fatal: log a warning and skip duplicate actions instead of returning 0
2. Check if actions are already registered before attempting registration
3. Document that local and ReaPack installs are mutually exclusive

---

### LTC hours >= 24 not recognized

- [x] Expand hour validation from 0-23 to 0-39 (LTC BCD encoding maximum)

**Symptom:** REAPER can output LTC with hours >= 24 (up to at least 24:59:59:FF). ReaTC rejects these frames at multiple validation points.

**Background:** The LTC BCD encoding uses 2+4 bits for hours (tens: 0-3, units: 0-9), supporting 0-39. SMPTE 12M defines 0-23, but REAPER and some systems use extended hours. The `% 24` wrapping in the encoder/MTC paths should stay as-is (MTC is strictly 0-23), but the LTC decoder and network outputs should accept extended hours.

**All validation points to update:**

| File | Line(s) | Current | Change to |
|---|---|---|---|
| `reatc_tc.jsfx` | 396, 401 | `hr < 24` | `hr < 40` (or desired max) |
| `reatc_artnet.py` | 108-110 | `0 <= hours <= 23` | `0 <= hours <= 39` |
| `reatc_osc.py` | 103-105 | `0 <= hours <= 23` | `0 <= hours <= 39` |
| `reatc_ui.lua` | 295 | `oh <= 23` | `oh <= 39` |
| `reatc_regions_to_ltc.lua` | 165 | `h > 23` | `h > 39` |
| `reatc_tc.jsfx` | 32, 44 | gmem docs say 0-23 | Update docs to reflect new range |

**Note:** The LTC *encoder* in the JSFX (`% 24` wrapping) and MTC quarter-frame generation should keep `% 24` since MTC is strictly 24-hour. Only the LTC *decoder* path and network outputs need the expanded range.
