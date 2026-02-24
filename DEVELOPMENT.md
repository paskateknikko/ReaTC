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

CI (`check.yml`) validates version format, CHANGELOG entry, and Python syntax on every push to `main`/`dev`.

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
| Lua ↔ JSFX | `gmem` shared memory (`ReaTC_LTC` namespace) | TC values, lock status, peak level, TC offset |
| Lua → Art-Net | Persistent subprocess (`reatc_artnet.py`) via `io.popen()` | UDP Art-Net TimeCode broadcast |
| Lua → OSC | Persistent subprocess (`reatc_osc.py`) via `io.popen()` | UDP OSC timecode broadcast |

#### Lua ↔ JSFX (`gmem`)

`gmem_attach("ReaTC_LTC")` creates a shared namespace between Lua and the JSFX. The JSFX writes TC values (H/M/S/F at `gmem[0–3]`), lock status (`gmem[4]`), peak level (`gmem[5]`), and a sequence counter (`gmem[6]`). Lua writes TC offset (H/M/S/F/sign at `gmem[20–24]`) which the JSFX applies before all outputs.

#### Lua → Art-Net Python (persistent subprocess)

`reatc_artnet.py` is launched once via `io.popen()` with its stdin kept open for the lifetime of the session. Lua writes `H:M:S:F fps\n` lines at ~25 Hz; the daemon parses each line and sends an Art-Net TimeCode UDP packet (port 6454) to the configured IP. The subprocess is restarted when the target IP changes.

#### Lua → OSC Python (persistent subprocess)

Same pattern as Art-Net. `reatc_osc.py` reads TC lines from stdin and sends `/tc ,iiiii H M S F type` OSC UDP messages to the configured IP and port.
