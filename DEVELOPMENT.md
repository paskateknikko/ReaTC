# Development

## Building from source

```bash
make              # build + verify + extension (VERSION=DEV)
make build v=1.0.0
make verify v=1.0.0
make extension    # build C++ extension
make watch        # auto-rebuild on file changes (requires watchexec)
make clean
```

The build substitutes `{{VERSION}}` placeholders in all source files and copies `src/` → `dist/`. Never edit files in `dist/` directly — always edit `src/` and rebuild.

To test locally, load `dist/Scripts/ReaTC/reatc.lua` in REAPER.

## Manual installation

1. Build or download a release archive
2. Copy `dist/Scripts/ReaTC` → REAPER Scripts directory:
   - **Windows**: `%APPDATA%\REAPER\Scripts\`
   - **macOS**: `~/Library/Application Support/REAPER/Scripts/`
3. Copy `dist/Effects/ReaTC` → REAPER Effects directory:
   - **Windows**: `%APPDATA%\REAPER\Effects\`
   - **macOS**: `~/Library/Application Support/REAPER/Effects/`
4. Copy the C++ extension binary to REAPER UserPlugins directory:
   - **Windows**: `%APPDATA%\REAPER\UserPlugins\reaper_reatc64.dll`
   - **macOS**: `~/Library/Application Support/REAPER/UserPlugins/reaper_reatc-arm64.dylib` (or `-x86_64.dylib` for Intel)

   Restart REAPER after adding the extension — native plugins are only loaded at startup.
5. In REAPER: Actions > Show action list > Load ReaScript > select `reatc.lua`

## Development environment

### 1. Install mise

[mise](https://mise.jdx.dev) manages Python and other dev tools across platforms.

- **macOS/Linux**: `curl https://mise.run | sh`
- **Windows**: `winget install jdx.mise`

### 2. Install project tools

```bash
mise install
```

This reads `.mise.toml` and installs Python 3.11 and watchexec.

### 3. Install `make`

`make` is required to run build commands.

- **macOS**: bundled with Xcode Command Line Tools — run `xcode-select --install` if missing
- **Windows**: `winget install GnuWin32.Make` or `choco install make`; Git Bash also bundles make

### 4. Restart REAPER

After installing Python, restart REAPER so it picks up the new binary.

No third-party Python packages are required.

## Release process

1. Update `CHANGELOG.md` with a `## [version] - date` entry
2. Commit all changes
3. Tag and push: `git tag -a v1.0.0 -m "v1.0.0" && git push origin v1.0.0`

GitHub Actions (`release.yml`) builds the project, publishes `dist/` to the `reapack` branch, and creates a GitHub Release automatically.

CI (`check.yml`) runs on every push to `main`/`dev`: build smoke test, artifact verification, unsubstituted-placeholder check, Lua syntax, Python syntax, pytest, and C++ extension build. CHANGELOG validation only happens in `release.yml` (on tag push).

## Architecture

`reatc.lua` is the entry point loaded by REAPER. It initializes submodules in dependency order and runs a deferred main loop:

```
reatc.lua (entry, defer loop)
├── reatc_core.lua    — constants, shared state, config persistence, TC math
├── reatc_outputs.lua — Art-Net + OSC output coordination (Python daemon management)
└── reatc_ui.lua      — ReaImGui UI (main view + settings modal)
```

Each module returns an object with a public API. All modules share a single `core.state` table.

The unified JSFX (`reatc_tc.jsfx`) handles all timecode sources (LTC decode, MTC decode, Timeline) and outputs (LTC encode, MTC generate, gmem bridge to Lua). It is manually inserted by the user from the FX browser — Lua does not manage tracks or FX chains.

### Standalone scripts

- `reatc_regions_to_ltc.lua` — bake LTC from regions tool with its own ImGui window

### C++ extension (`src/extension/`)

A native REAPER plugin that registers custom action IDs so ReaTC can be controlled via OSC, MIDI controllers, or any REAPER action trigger.

| Action ID | Display Name | Behaviour |
|---|---|---|
| `_REATC_MAIN` | ReaTC: Launch/toggle UI | Runs `reatc.lua` via `AddRemoveReaScript` |
| `_REATC_BAKE_LTC` | ReaTC: Regions to LTC | Runs `reatc_regions_to_ltc.lua` |
| `_REATC_TOGGLE_ARTNET` | ReaTC: Toggle Art-Net output | Sets `ExtState("ReaTC_CMD", "toggle_artnet")` |
| `_REATC_TOGGLE_OSC` | ReaTC: Toggle OSC output | Sets `ExtState("ReaTC_CMD", "toggle_osc")` |

Toggle actions (`ARTNET`, `OSC`) report on/off state via `toggleaction` hook, reading from `ExtState("ReaTC_STATE", ...)` written by the Lua script.

**Building:**

```bash
make extension          # CMake build → dist/extension-build/
```

Requires CMake 3.15+ and a C++17 compiler. On macOS, Xcode Command Line Tools are sufficient. Deployment targets are read from `build/platforms.env`.

**Output binaries** (included in releases via `@provides` platform entries):
- macOS ARM64: `reaper_reatc-arm64.dylib`
- macOS x86_64: `reaper_reatc-x86_64.dylib`
- Windows: `reaper_reatc64.dll`

**Installation:** place the `.dylib`/`.dll` in REAPER's `UserPlugins/` directory. ReaPack handles this automatically via the `[extension ...]` provides entries.

### IPC channels

| Channel | Mechanism | Used For |
|---|---|---|
| Lua ↔ JSFX | `gmem` shared memory (`ReaTC_LTC` namespace) | TC values, lock status, TC offset |
| C++ → Lua | `ExtState` (`ReaTC_CMD` section, consumed once) | Toggle Art-Net/OSC from action triggers |
| Lua → C++ | `ExtState` (`ReaTC_STATE` section, read-only by C++) | Current toggle state for Actions list indicators |
| Lua → C++ (API) | `reaper.ReaTC_SetTC` / `ReaTC_SetArtNetOutput` / `ReaTC_SetOSCOutput` | TC + output settings; the extension sends Art-Net TimeCode / OSC UDP packets once per frame |
| Lua → C++ (API) | `reaper.ReaTC_ListInterfaces` | Local IPv4 interfaces for Preferred IP / Interface |

#### Lua ↔ JSFX (`gmem`)

`gmem_attach("ReaTC_LTC")` creates a shared namespace between Lua and the JSFX. The JSFX writes TC values (H/M/S/F at `gmem[0–3]`), framerate (`gmem[4]`), play state (`gmem[5]`), validity flag (`gmem[6]`), write counter (`gmem[7]`), frame start time (`gmem[9]`, `time_precise()` when the current output frame began — from the play position's sub-frame phase for Timeline, the block a new frame appeared in for LTC/MTC), running flag (`gmem[10]`), active source (`gmem[17]`), and lock status (`gmem[18–19]` for LTC/MTC). Lua writes a heartbeat (`gmem[8]`) and TC offset (H/M/S/F/sign at `gmem[20–24]`) which the JSFX applies before all outputs. Peak level is a local variable exposed via slider, not gmem.

#### Lua → C++ network API

The extension registers ReaScript functions (`src/extension/reaper_reatc.cpp`):

| Function | Returns |
|---|---|
| `ReaTC_GetVersion()` | extension version (CMake `REATC_VERSION`, set from the release tag) |
| `ReaTC_ListInterfaces()` | tab-separated `ip  name  broadcast-or-dash  netmask` rows for up, non-loopback IPv4 interfaces |
| `ReaTC_SetTC(valid, h, m, s, f, type, running, age)` | — (TC the outputs follow; `age` = seconds since the current frame started) |
| `ReaTC_SetArtNetOutput(enabled, dests, srcIP, streamID)` | — |
| `ReaTC_SetOSCOutput(enabled, destIP, port, address, srcIP)` | — |
| `ReaTC_GetPacketCount(kind)` | `"artnet"` / `"osc"`: packets sent since the output was enabled |
| `ReaTC_GetLastError(kind)` | error from the most recent send, or `""` |
| `ReaTC_GetLastWarning(kind)` | bind warning (source IP could not be bound, default route used), or `""` |

The Lua defer loop calls the `Set*` functions every cycle (~30 Hz); that is too coarse to send per frame (a 40 ms throttle polled every ~33 ms hits every other frame at 25 fps). Instead a sender thread in the extension (`reatc_output.cpp`) runs a frame clock (`reatc_clock.h`): it anchors on the reported frame and its start time, sends each frame once on its boundary while TC is running, re-locks on every update without ever stepping back, and repeats the held frame once per frame period while paused. It stops extrapolating after 0.5 s without a fresh frame and stops sending after 1 s without any `ReaTC_SetTC` call (script closed). Each output keeps one UDP socket (`SO_BROADCAST`, optionally bound to the Preferred IP / Interface address) that is rebuilt when the source IP changes; destinations are re-parsed when the string changes, so settings edits apply on the next packet. Packet builders and frame math live in the header-only `reatc_packets.h`, the frame clock in `reatc_clock.h`; both are covered by `src/extension/tests/test_packets.cpp`:

```bash
cmake -S src/extension -B src/extension/build -DREATC_BUILD_TESTS=ON
cmake --build src/extension/build --config Release
ctest --test-dir src/extension/build -C Release
```

Without the extension, Art-Net and OSC output are unavailable and the UI says so. Python is only used by *Bake LTC from regions* (`reatc_ltcgen.py`).
