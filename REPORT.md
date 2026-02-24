# ReaTC Code Review Report

**Date:** 2026-02-24
**Scope:** Full codebase (~3,800 LOC) — Lua scripts, Python daemons, C++ extension, JSFX processor, build system, CI/CD
**Version reviewed:** dev branch (pre-v1.1.0)

---

## 1. Executive Summary

ReaTC is well-structured for a REAPER plugin ecosystem. The architecture is clean — JSFX handles real-time audio/MIDI, Lua orchestrates UI and networking via Python daemons, and a C++ extension provides REAPER action integration. The gmem IPC contract is well-documented in the JSFX header.

**Finding counts by severity:**

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 3 |
| MEDIUM | 6 |
| LOW | 10 |
| NOTE | 4 |
| **Total** | **23** |

No critical issues found. The HIGH findings are: silent discard of malformed daemon input (ERR-001), no Lua syntax validation in CI (CI-001), and no TC range validation in Python daemons (BUG-001).

**Resolution summary:** 17 findings fixed, 6 accepted as-is (design decisions or negligible risk).

---

## 2. Bugs & Correctness

### BUG-001 [HIGH] Python daemons: no TC range validation
**Files:** `src/Scripts/ReaTC/reatc_artnet.py`, `src/Scripts/ReaTC/reatc_osc.py`

Parsed integer values from stdin are passed directly to packet builders without range checks. Out-of-range values (e.g., hours > 23, frames > 29) would produce invalid Art-Net/OSC packets. While the Lua sender already constrains values, defense-in-depth requires validation at the daemon boundary.

**Status:** [x] Fixed (P2-01) — Added range validation and stderr logging

### BUG-002 [MEDIUM] Daemon write failure permanently disables output
**Files:** `src/Scripts/ReaTC/reatc_outputs.lua`

When `pcall` catches a write failure, the daemon is stopped **and** the output is disabled. The user must manually re-enable in settings. A transient pipe break (e.g., Python crash) should retry before giving up.

**Status:** [x] Fixed (P2-07) — Added 3-retry backoff before disabling

### BUG-003 [LOW] 29.97fps float approximation — accepted risk
**Files:** `src/Scripts/ReaTC/reatc_core.lua:21`, `src/Scripts/ReaTC/reatc_ltcgen.py:28`

`FPS_VAL` stores 29.97 as a float. TC conversion uses integer math for drop-frame, so the float is only used for sample-boundary rounding. Accepted risk — no action needed.

**Status:** [x] Accepted

### BUG-004 [NOTE] MTC minute rollover at mid-cycle — correct but subtle
**Files:** `src/Effects/ReaTC/reatc_tc.jsfx` (MTC decoder section)

The MTC quarter-frame decoder correctly handles mid-cycle minute rollover by only reporting TC after a full 8-piece cycle completes (`mtc_in_got_first_full` flag). This is correct but non-obvious.

**Status:** [x] Comment added (Pass 3) — Documented mtc_in_got_first_full guard in JSFX

### BUG-005 [MEDIUM] `os.execute` return unchecked in region bake
**Files:** `src/Scripts/ReaTC/reatc_regions_to_ltc.lua`

`os.execute(cmd)` for LTC generation and `mkdir` didn't check return values.

**Status:** [x] Fixed (P2-05) — Both mkdir and generation return values now checked

### BUG-006 [NOTE] JSFX sync word 0xBFFC vs 0x3FFD
**Files:** `src/Effects/ReaTC/reatc_tc.jsfx`, `src/Scripts/ReaTC/reatc_ltcgen.py`

Both are valid representations of the same SMPTE 12M sync pattern (LSB-first vs MSB-first ordering). No action needed.

**Status:** [x] Accepted

### BUG-007 [LOW] `reatc_ltcgen.py` amplitude overflow possible
**Files:** `src/Scripts/ReaTC/reatc_ltcgen.py`

CLI amplitude argument parsed as `int()` with no clamping. Values > 32767 overflow int16 PCM.

**Status:** [x] Fixed (P2-04) — Added `max(1, min(32767, ...))` clamp

---

## 3. Error Handling

### ERR-001 [HIGH] Silent discard of malformed input in Python daemons
**Files:** `src/Scripts/ReaTC/reatc_artnet.py`, `src/Scripts/ReaTC/reatc_osc.py`

Both daemons caught `ValueError`/`IndexError` and `continue` without any logging.

**Status:** [x] Fixed (P2-01) — Now logs to stderr on malformed/out-of-range input

### ERR-002 [MEDIUM] No daemon process health monitoring or auto-restart
**Files:** `src/Scripts/ReaTC/reatc_outputs.lua`

When a daemon write failed, the output was immediately disabled with no retry mechanism.

**Status:** [x] Fixed (P2-07) — 3-retry with exponential backoff (0.5s, 1s, 2s)

### ERR-003 [LOW] `build.py` opens files without explicit `encoding="utf-8"`
**Files:** `build/build.py`, `build/verify.py`

Python's `open()` defaults to the platform's locale encoding.

**Status:** [x] Fixed (P2-03) — All `open()` calls now specify `encoding="utf-8"`

### ERR-004 [LOW] Inconsistent pcall usage across Lua scripts
**Files:** `src/Scripts/ReaTC/reatc_outputs.lua`, `src/Scripts/ReaTC/reatc_ui.lua`

**Status:** [x] Accepted (REAPER handles script errors)

---

## 4. Performance

### PERF-001 [LOW] Fixed 30Hz output throttle regardless of framerate
**Files:** `src/Scripts/ReaTC/reatc_outputs.lua`

Both `send_osc()` and `send_artnet()` throttled at `1/30` Hz regardless of the configured framerate.

**Status:** [x] Fixed (P2-12) — Throttle now matches active framerate from `core.FPS_VAL`

### PERF-002 [LOW] No gmem dirty tracking — accepted
**Status:** [x] Accepted

### PERF-003 [LOW] Python daemon startup latency on first TC send
**Files:** `src/Scripts/ReaTC/reatc_outputs.lua`

Daemons started lazily on the first `send_*()` call, causing 100-300ms first-packet delay.

**Status:** [x] Fixed (P2-13) — Added `prestart_daemons()` called after settings load

### PERF-004 [LOW] Per-frame bytearray allocation in ltcgen.py
**Status:** [x] Accepted

---

## 5. Security

### SEC-001 [MEDIUM] No dest_ip validation in Python daemons
**Status:** [x] Accepted (Lua validates before launching)

### SEC-002 [LOW] OSC address not validated
**Files:** `src/Scripts/ReaTC/reatc_ui.lua`

The OSC address field accepted any string. The OSC spec requires addresses to start with `/`.

**Status:** [x] Fixed (P2-06) — UI now validates OSC address starts with `/`

---

## 6. Architecture

### ARCH-001 [MEDIUM] gmem indices hardcoded in Lua, named in JSFX
**Files:** `src/Scripts/ReaTC/reatc_core.lua`, `src/Scripts/ReaTC/reatc.lua`, `src/Effects/ReaTC/reatc_tc.jsfx`

JSFX defined named constants but Lua used raw magic numbers.

**Status:** [x] Fixed (P2-10) — Added `GMEM_*` constants to core, updated all call sites

### ARCH-002 [LOW] Settings keys are scattered string literals
**Files:** `src/Scripts/ReaTC/reatc_core.lua`

Settings keys were string literals in both `load_settings()` and `save_settings()`.

**Status:** [x] Fixed (P2-14) — Extracted `SK` (settings keys) constant table

### ARCH-003 [LOW] Python daemon stdin protocol undocumented in Lua
**Files:** `src/Scripts/ReaTC/reatc_outputs.lua`

The stdin protocol was only documented in the Python scripts' headers.

**Status:** [x] Comment added (Pass 3) — Added `-- stdin protocol: "H M S F fps_type\n"` comments

### ARCH-004 [NOTE] JSFX GFX source rows are copy-paste
**Status:** [x] Accepted (unavoidable in JSFX)

### ARCH-005 [LOW] Magic numbers scattered throughout
**Status:** [x] Partially addressed (P2-10, P2-12) — gmem indices and throttle rate now named

### ARCH-006 [NOTE] Color palette duplicated between UI scripts
**Status:** [x] Accepted (intentional — standalone script)

---

## 7. Build System

### BUILD-001 [LOW] File encoding not specified in build.py/verify.py
**Status:** [x] Fixed (P2-03) — Same as ERR-003

### BUILD-002 [NOTE] No warning for unsubstituted placeholders during build
**Status:** [x] Accepted (CI grep check is sufficient)

---

## 8. CI/CD

### CI-001 [HIGH] No Lua syntax validation in CI
**Files:** `.github/workflows/check.yml`

CI validated Python syntax but not Lua.

**Status:** [x] Fixed (P2-02) — Added `luac5.3 -p` syntax check step

### CI-002 [MEDIUM] Extension only built on Linux in CI
**Status:** [x] Accepted (release workflow covers cross-platform)

### CI-003 [LOW] No mise/Python build caching
**Files:** `.github/workflows/check.yml`

Each CI run installed mise and Python from scratch.

**Status:** [x] Fixed (P2-11) — Added `actions/cache@v4` for mise tools

### CI-004 [MEDIUM] No unit tests exist

**Status:** [x] Fixed (P2-08, P2-09) — Created `tests/test_artnet.py`, `tests/test_osc.py`, `tests/test_ltcgen.py`, `tests/test_build.py` with pytest runner in CI

---

## 9. Testing Strategy

### What's Testable (Python pytest)

| Component | Test Target | Type |
|-----------|------------|------|
| `reatc_artnet.py` | `build_artnet_timecode()` — packet structure, field positions, byte order | Unit |
| `reatc_osc.py` | `osc_string()` — padding, null-termination; `build_osc_timecode()` — packet layout | Unit |
| `reatc_ltcgen.py` | `build_ltc_frame()` — BCD encoding, sync word, BMPC parity; `advance_tc()` — rollover, drop-frame skip; `render_frame()` — sample count, polarity | Unit |
| `build/build.py` | `substitute_version()`, `read_changelog_for_version()` | Unit |
| `build/verify.py` | `parse_platforms_env()`, `verify_badges()` | Unit |

### What's NOT Testable Outside REAPER

- **JSFX** — no standalone interpreter exists
- **C++ extension** — requires REAPER SDK runtime
- **Lua UI** — requires ReaImGui and REAPER API
- **Integration testing** — gmem IPC requires REAPER process

---

## 10. Documentation Gaps

### DOC-001 [MEDIUM] No manual installation section in README
**Status:** [x] Fixed (Pass 3) — Added "Manual Installation" section to README.md

### DOC-002 [LOW] No troubleshooting section in README
**Status:** [x] Fixed (Pass 3) — Added "Troubleshooting" section with common issues

### DOC-003 [LOW] Architecture diagram missing ExtState IPC
**Status:** [x] Fixed (Pass 3) — Added C++ Extension with ExtState arrows in diagram

### DOC-004 [LOW] Architecture diagram missing reatc_ltcgen.py
**Status:** [x] Fixed (Pass 3) — Added standalone scripts subgraph with ltcgen.py

### DOC-005 [NOTE] Architecture diagram filename typo
**Status:** [x] Fixed (P2-15) — Created `docs/architecture.mmd` (old file preserved)

### DOC-006 [LOW] No inline documentation on public APIs
**Status:** [x] Fixed (Pass 3) — Added LDoc annotations (Lua), type hints + docstrings (Python), Doxygen comments (C++), section headers (JSFX)
