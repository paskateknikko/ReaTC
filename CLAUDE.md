# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

ReaTC is a REAPER extension that syncs REAPER with lighting consoles via Art-Net and MIDI TimeCode. It consists of Lua scripts (with ReaImGui UI), a JSFX DSP plugin for LTC audio decoding/generation, and Python daemons for network and MIDI output.

## Build Commands

```bash
make              # Build and verify (default target)
make build        # Substitute {{VERSION}} placeholders and copy src/ → dist/
make verify       # Check all dist/ files exist with correct version string
make clean        # Remove dist/
make watch        # Auto-rebuild on file changes (requires watchexec)
```

The build system reads `version.txt` as the single source of truth for version. All source files use `{{VERSION}}` as a placeholder that `build/build.py` substitutes at build time. **Never edit files in `dist/` directly — always edit `src/` and rebuild.**

To test, load `dist/Scripts/ReaTC/ReaTC.lua` in REAPER.

## Release Process

1. Update `version.txt` with the new semantic version
2. Add a `## [version] - date` entry to `CHANGELOG.md`
3. Commit, then: `git tag -a v1.0.x -m "..."` and `git push origin v1.0.x`
4. GitHub Actions (`release.yml`) builds, publishes `dist/` to the `reapack` branch, and creates a GitHub Release

CI (`check.yml`) validates version format, CHANGELOG entry, and Python syntax on every push to `main`/`dev`.

## Architecture

### Module Structure

`ReaTC.lua` is the entry point loaded by REAPER. It initializes submodules in dependency order and runs a deferred main loop:

```
ReaTC.lua (entry, defer loop)
├── reatc_core.lua   — constants, shared state object, config persistence, TC math
├── reatc_ltc.lua    — JSFX bridge (insert/find/read the LTC decoder plugin)
├── reatc_outputs.lua — Art-Net + MTC output coordination
└── reatc_ui.lua     — ReaImGui UI (main view + settings view)
```

Each module returns an object with a public API. All modules share a single `core.state` table. Initialization is chained: each module receives the core object and registers itself before the main loop starts.

### IPC Patterns

There are three distinct IPC mechanisms:

| Channel | Mechanism | Used For |
|---|---|---|
| Lua ↔ JSFX | `gmem` shared memory (`ReaTC_LTC` namespace) + FX slider reads | LTC TC values, lock status, peak level |
| Lua → MTC Python | Persistent subprocess via `io.popen()`, commands sent to stdin | MIDI Quarter-Frame and SysEx output |
| Lua → Art-Net Python | Spawn `reatc_udp.py` per packet | UDP Art-Net TimeCode broadcast |

### JSFX Plugin (`reatc_ltc.jsfx`)

Dual-mode plugin running as a REAPER FX on the selected LTC track:
- **Transport mode**: Generates LTC audio from REAPER's play position
- **LTC Input mode**: Decodes incoming audio using biphase-mark decoding, with rate auto-detection and configurable threshold

`reatc_ltc.lua` manages inserting this plugin into the correct track's FX chain, reading its slider outputs each frame, and resetting state on track change.

### Python Daemons

- `reatc_udp.py`: Stateless subprocess, builds a 19-byte Art-Net TimeCode UDP packet and exits
- `reatc_mtc.py`: Long-lived daemon that reads `play`/`stop` commands from stdin, sends MIDI Quarter-Frame messages at frame-rate-accurate intervals with drift recovery, and sends SysEx full-frame locate messages

### Config Persistence

Settings are stored via REAPER's `ExtState` API (in `reatc_core.lua`). There is no external config file.

## Key Conventions

- **`{{VERSION}}`** must appear in all source files that need version info — the build substitutes it
- Python binary detection tries 9+ candidates including Windows paths — see `reatc_core.lua`
- Cross-platform path handling: use `2>/dev/null` (macOS/Linux) or `2>NUL` (Windows) where needed
- The `reapack` git branch is machine-managed by CI — never push to it manually
