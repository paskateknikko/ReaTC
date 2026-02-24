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


## [1.0.0] - 2026-02-24

First public release

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
- **C++ extension** — registers custom REAPER action IDs (`_REATC_MAIN`, `_REATC_BAKE_LTC`, `_REATC_TOGGLE_ARTNET`, `_REATC_TOGGLE_OSC`) for OSC/MIDI controller automation
- **All standard frame rates** — 24fps (Film), 25fps (EBU/PAL), 29.97fps Drop Frame, 30fps (SMPTE)
- **Dark UI** — Lua window and JSFX share a unified dark visual style; TC display and text scale proportionally when resizing
- **Cross-platform** — macOS (10.15+) and Windows (10+); Python 3 standard library only
- **ReaPack compatible** — install via package manager; ReaImGui auto-installed as dependency
