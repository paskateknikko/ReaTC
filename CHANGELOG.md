All notable changes to ReaTC — the REAPER timecode bridge for lighting and media — will be documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning: `MAJOR.MINOR.PATCH[-PRE]` per [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

| Example         | When             | Bump      |
|-----------------|------------------|-----------|
| `2.0.0`         | Breaking changes | **MAJOR** |
| `1.1.0`         | New features     | **MINOR** |
| `1.0.1`         | Bug fixes        | **PATCH** |
| `X-X-X-beta-1`  | Pre-release      | **PRE**   |
--------------------------------------------------

# ReaTC Changelog

## [1.2.1] - 2026-04-04

### Changed

- **Local build naming** — `make all` / `make install` now names the extension binary with architecture suffix matching CI artifacts (e.g. `reaper_reatc-arm64.dylib`)

### Fixed

- **LTC extended hours** — accept LTC timecode with hours 0-39 (full BCD range); REAPER and some systems output hours >= 24 which were previously rejected
- **Duplicate extension loading** — C++ extension no longer fatally exits when action IDs are already registered (e.g. local + ReaPack install coexisting); logs a warning instead

## [1.2.0] - 2026-04-04

### Added

- **Open Script button in JSFX** — launch the Lua script directly from the JSFX GUI when it's not running
- **LTC User Bits** — set user bits format (None/Characters/Date-Timezone) and 4-byte value in the JSFX settings; numeric input with Tab/Shift-Tab navigation; defaults to Characters mode matching REAPER
- **BGF Position Mode** — choose SMPTE (REAPER-compatible) or EBU standard bit positions at 25fps
- **LTC Diagnostics JSFX** — new analysis plugin with responsive UI, waveform display, frame bit histogram, timing histogram, decoder statistics, auto-detected frame rate, and auto-detected BGF positioning (SMPTE/EBU)
- **Clickable output toggles** — Art-Net and OSC can now be toggled directly from the main window
- **`make install`** — one-command build and install to your REAPER resource folder

### Changed

- **All timecode outputs always active** — LTC and MTC run whenever valid TC is present, even when stopped; enables live format conversion (e.g. MTC→LTC)
- **LTC waveform** — slew-rate limiter replaces low-pass filter; produces clean trapezoidal wave matching REAPER's LTC generator (flat tops, no droop)
- **Unified install paths** — manual install now matches the ReaPack layout; one zip, extract and go
- **Cleaner main window** — less whitespace, TC scales to fit window, version shown inline
- **Settings closes on ESC**
- **OSC port** — plain text field instead of +/- stepper

### Fixed

- **Source display stuck on "No active source"** — JSFX gmem variables silently overwritten due to EEL2 local variable pool overflow; all gmem indices and frame builder now use hardcoded values
- **Open Script button** — now works from any JSFX instance, not just the first one
- **LTC output level** — peak level now matches configured dBFS exactly
- **BGF flags at 25fps** — correct bit positions for both SMPTE and EBU conventions; parity no longer bleeds into BGF1

### CI / DEV

- **`build/reapack.env`** — single source of truth for ReaPack index name and category
- **Dist structure** — `dist/ReaTC-{VERSION}/` with full REAPER resource folder layout; CI produces a single zip with all platforms

## [1.1.1] — 2026-03-03

### Fixed

- MTC output running at half speed — QF cycle now correctly advances by 2 frames per 8-piece cycle

## [1.1.0] — 2026-02-27

First public release.

### Timecode Sources

- **LTC audio decoder** — real-time biphase-mark decoding with adaptive clock recovery (IIR filter); auto-detects frame rate (24/25/29.97DF/30); configurable threshold; supports varispeed LTC
- **MTC input decoder** — parses incoming MIDI quarter-frame messages and full-frame SysEx; mid-cycle reporting (every frame instead of every 2 frames); instant locate via Full Frame SysEx; 2-frame lag compensation
- **REAPER Timeline** — reads timecode directly from transport play position
- **Source priority system** — each source configurable as High/Normal/Low priority with automatic failover; ties broken LTC > MTC > Timeline

### Timecode Outputs

- **Art-Net TimeCode** — broadcasts SMPTE TC over UDP (port 6454); unicast or broadcast destination; configurable IP
- **MIDI Timecode (MTC)** — JSFX-native quarter-frame generator at sample-accurate offsets; no external MIDI library required
- **OSC** — broadcasts SMPTE TC as raw OSC (`/tc ,iiiii H M S F type`) at ~30 fps; configurable destination IP, port, and OSC address
- **LTC audio generator** — encodes timecode to LTC audio with rise-time filtering per SMPTE 12M spec; configurable output level
- **Bake LTC from regions** — standalone tool generates offline LTC WAV files from project regions; per-region TC start, FPS, and selection; configurable output level, track, and filename template

### Features

- **TC Offset** — user-configurable HH:MM:SS:FF offset applied inside the JSFX before all outputs; supports add/subtract, drop-frame wrap-around, and 24-hour wrap; persisted across sessions
- **Unified Timecode Converter JSFX** — single `reatc_tc.jsfx` plugin handles all TC sources and outputs with interactive @gfx UI
- **Network sync status** — Art-Net and OSC indicators show packet counts and daemon health (green/red/orange)
- **JSFX detection warning** — Lua script shows orange warning when the JSFX is not loaded or has Script Output disabled
- **C++ extension** — registers custom REAPER action IDs (`_REATC_MAIN`, `_REATC_BAKE_LTC`, `_REATC_TOGGLE_ARTNET`, `_REATC_TOGGLE_OSC`) for OSC/MIDI controller automation; prints load confirmation with assigned command IDs to REAPER console
- **All standard frame rates** — 24fps (Film), 25fps (EBU/PAL), 29.97fps Drop Frame, 30fps (SMPTE)
- **Dark UI** — Lua window and JSFX share a unified dark visual style; TC display and text scale proportionally when resizing
- **Cross-platform** — macOS (10.15+) and Windows (10+); Python 3 standard library only
- **ReaPack compatible** — install via package manager; ReaImGui auto-installed as dependency
