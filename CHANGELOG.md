# Changelog

All notable changes to ReaTC will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [1.1.0] - 2026-02-23

### Fixed

- **Drop-frame TC incorrect at 10-minute boundaries**: formula was producing garbage TC (~23:59:59;28) and 2-frame glitches at 10:00, 20:00, etc. — fixed with `max(0, floor((mm - 2) / 1798))` guard in both Lua and EEL2
- **LTC re-encoding not active in LTC Input mode**: encoder only ran in Transport mode, leaving mode 1 with no output — now re-clocks decoded LTC in both modes  
- **Negative play_position not clamped**: REAPER allows cursor positions before project start, causing garbage TC — added `max(0, pos)` clamp in both `tc_from_pos_*` functions
- **Sample rate changes mid-session not detected**: decoder/encoder cached timing constants from init only; audio device switch left thresholds and rates stale — added runtime detection in `@block`
- **Peak decay applied per-block not per-sample**: exponent used `samplesblock / srate` instead of `1.0 / srate`, zeroing peak instantly — fixed exponential decay calculation
- **Stale MediaTrack pointer after deletion**: Lua cached track handle without validation; deleted track became dangling — added `reaper.ValidatePtr()` check
- **slider_automate(slider10) automating wrong slider**: passed value (0/1) instead of bitmask — fixed with `slider_automate(1<<9)` for slider10
- **Art-Net spawning Python ~30 times/second**: each packet spawned new process (fork+exec overhead) — converted to persistent daemon (socket reuse)
- **LTC track lost on reorder/add/delete**: stored 0-based index which changed silently — now persists track GUID, resolvable even after project restructuring
- **UI frozen during pip install**: `os.execute()` blocked script — made async with `start` (Windows) or `&` (Unix)
- **Redundant frame rebuild in @slider**: `build_enc_frame()` called but frame was stale (rebuilt immediately in @block) — removed call
- **dec_seq incremented every @block wastefully**: 512-sample blocks (94/sec) vs TC frames (24–30/sec) = 60–70% redundant Lua reads — now only increments on TC change
- **No IP address validation**: malformed IPs passed to Python silently failed — added `is_valid_ipv4()` with octet range checks

### Improved

- **NDF framerate calculation**: changed from `fps` (float) to `int_fps` for clearer intent in non-drop-frame path
- **Thread-safety documentation**: added comment explaining benign race between @sample/@block (audio) and @gfx (GUI) threads — momentary stale display only
- **IP configuration error feedback**: now validates on save/load and shows error message for malformed addresses
- **Art-Net daemon startup**: daemon only created on first packet send (lazy init), restarted if IP address changes

### New Files

- **reatc_artnet.py**: persistent Art-Net TimeCode daemon (replaces per-packet reatc_udp.py for this function)

### Technical Notes

- JSFX LTC encoder now always active (both Transport and LTC Input modes)
- Track persistence via GUID + fallback: script resolves GUID each session; if GUID not found, no automatic fallback to index (explicit re-selection required)
- Art-Net daemon restarts on IP change to apply new destination


## [1.0.1] - 2026-02-23

### Added

- **LTC rate detection**: automatically detects incoming LTC frame rate (24/25/29.97DF/30) using a 2-second observation window with frame count guard (≥10 frames)
- **Rate mismatch warning**: orange warning in status row when detected LTC rate differs from configured rate
- **LTC detected indicator**: "LTC DETECTED" label shown in Transport mode when LTC signal is present on input
- **gmem shared memory**: JSFX ↔ Lua communication via named `ReaTC_LTC` namespace for script-alive signalling

### Fixed

- **Transport mode TC not reaching Lua**: `dec_seq` was never incremented in Transport mode, so the Lua bridge never detected new timecode — now increments each `@block`
- **Transport TC stuck at 00:00:00:00**: replaced invalid `transport_pos`/`transport_playing` with correct JSFX built-ins `play_position`/`play_state`
- **play_state overwrite**: local assignment clobbered the JSFX built-in variable — renamed local to `is_playing`
- **OFFLINE/RUNNING badge always wrong**: `gmem_attach("ReaTC_LTC")` was never called in JSFX or Lua, and Lua never wrote to gmem[8] — fixed both sides
- **Rate detection false positive**: mismatch warning no longer fires on startup before enough frames are observed

### Changed

- Increased all JSFX UI font sizes by 1–2 pt for better readability
- Brightened dim/hint text colors (0.45–0.55 → 0.62–0.70 range)
- Removed threshold slider from JSFX UI (still controllable via Lua/REAPER slider panel)
- Mode button now spans full panel width with centered label
- Mode description text centered above mode button
- Drop-frame timecode uses semicolon separator (`;`) per SMPTE convention
- Background color tint varies by mode (cool blue-black for Transport, warm dark for LTC Input)

## [1.0.0] - 2026-02-22

### Changed

- **ReaPack branch renamed**: `gh-pages` → `reapack` for clarity and self-documentation
- **ReaPack URL updated**: `https://github.com/paskateknikko/ReaTC/raw/reapack/index.xml`
  - index.xml now only published to reapack branch (not tracked in main)
  - Fully automated workflow (no manual commits needed)
  - Single source of truth for distribution
- Build script generates index.xml only in `dist/` directory
- Added index.xml to .gitignore

### Migration

If you installed previous versions, update your ReaPack repository URL:
1. Extensions > ReaPack > Manage repositories
2. Find ReaTC, click Edit
3. Update URL to: `https://github.com/paskateknikko/ReaTC/raw/reapack/index.xml`

## [1.0.0-pre2] - 2026-02-22

### Added

- ReaPack `@provides` tag: explicit file list ensures proper package installation
- ReaPack `@link reapack` dependency: ReaImGui auto-installed when ReaTC is installed
- `@version` tags in all library files for version tracking
- `@noindex` tags in library files to prevent them appearing as standalone packages

### Changed

- ReaImGui listed as automatic dependency (installed via ReaPack)
- Updated requirements documentation in @about section

## [1.0.0-pre1] - 2026-02-22

### Added

- ReaImGui UI: all settings widgets (checkbox, combo, slider, IP input) now use native ReaImGui controls — no more custom gfx primitives
- ReaPack `@about` metadata block in `ReaTC.lua` (Markdown, rendered in ReaPack's "About" dialog)
- `build.py`: `parse_about_from_script()` extracts the `@about` block and converts it to RTF for `index.xml` — single source of truth for package description

### Changed

- **Requires ReaImGui** (install via ReaPack → ReaTeam Extensions → ReaImGui); script shows a dialog and exits gracefully if missing
- `reatc_ui.lua` fully rewritten: removed `update_mouse()`, `handle_key()`, and all `gfx.*` helper functions

## [0.0.5] - 2026-02-22

### Added

- ReaPack About text via RTF description

## [0.0.4] - 2026-02-22

### Changed

- ReaPack URLs now use the github.com/.../raw/... format
- ReaPack index generation uses changelog entries for release notes

## [0.0.3] - 2026-02-22

### Added

- Repo-root `index.xml` for ReaPack repository discovery
- gh-pages publishing of built ReaPack files from GitHub Actions

### Changed

- ReaPack install URL updated to `https://raw.githubusercontent.com/paskateknikko/ReaTC/main/index.xml`
- ReaPack source file URLs now point to `gh-pages` for stable hosting

## [0.0.2] - 2026-02-22

### Added

- Automated GitHub Releases workflow that builds and packages ReaTC on version tags
- ReaPack index metadata improvements with correct repository URLs and all script sources
- Release zip artifact generation for GitHub Releases

### Changed

- Build scripts tracked in git for CI compatibility
- ReaPack install URL updated to the correct GitHub repository


## [0.0.1] - 2026-02-22

### Features

- **Real-time TC transmission** from REAPER transport position or LTC audio input
- **Multiple TC sources**:
  - REAPER transport position (default)
  - LTC audio decoding from any track via Lua + REAPER audio accessor
- **Art-Net TimeCode output** via UDP (port 6454)
- **MIDI TimeCode (MTC) output** via virtual or hardware MIDI ports
- **All standard frame rates**: 24fps (Film), 25fps (EBU/PAL), 29.97fps (Drop Frame), 30fps (SMPTE)
- **Unicast or broadcast** destination for Art-Net
- **Large TC monitor display** with visual feedback
- **Cross-platform support**: Windows and macOS
- **ReaPack compatible** for easy installation via package manager

### Requirements

- REAPER 6.0 or higher
- Python 3 (pre-installed on macOS; download from https://python.org on Windows)
- python-rtmidi (optional, for MTC output) - auto-installed on first MTC enable

### Technical Details

- **Art-Net Implementation**: Standard DMX512-over-Ethernet protocol
- **Frame Rate Support**: SMPTE and EBU standards
- **LTC Decoding**: Sub-frame accuracy timecode detection from audio
- **MIDI**: Full Frame and Quarter Frame messages per MTC spec
