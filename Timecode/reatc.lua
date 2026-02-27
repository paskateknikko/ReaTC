-- @description Art-Net and MIDI Timecode sender for REAPER
-- @author Tuukka Aimasmäki
-- @version 1.1.0
-- @link https://github.com/paskateknikko/ReaTC
-- @about
--   # ReaTC
--   Sync REAPER with your lighting console using Art-Net, MIDI Timecode, and OSC.
--
--   **Sources**: LTC audio, MIDI Timecode, REAPER Timeline (priority-based failover)
--   **Outputs**: Art-Net, MTC, OSC, LTC audio, Region-based LTC bake
--
--   Requires REAPER 6.32+, ReaImGui, Python 3. Cross-platform (macOS 10.15+, Windows 10+).
--
--   [GitHub](https://github.com/paskateknikko/ReaTC)
-- @provides
--   [main] reatc.lua
--   [main] reatc_regions_to_ltc.lua
--   reatc_core.lua
--   reatc_ui.lua
--   reatc_outputs.lua
--   reatc_*.py
--   [extension darwin-arm64] reaper_reatc-arm64.dylib
--   [extension darwin64] reaper_reatc-x86_64.dylib
--   [extension win64] reaper_reatc64.dll
-- @changelog
--   First public release.
-- 
-- ### Timecode Sources
-- 
-- - **LTC audio decoder** — real-time biphase-mark decoding with adaptive clock recovery (IIR filter); auto-detects frame rate (24/25/29.97DF/30); configurable threshold; supports varispeed LTC
-- - **MTC input decoder** — parses incoming MIDI quarter-frame messages and full-frame SysEx; mid-cycle reporting (every frame instead of every 2 frames); instant locate via Full Frame SysEx; 2-frame lag compensation
-- - **REAPER Timeline** — reads timecode directly from transport play position
-- - **Source priority system** — each source configurable as High/Normal/Low priority with automatic failover; ties broken LTC > MTC > Timeline
-- 
-- ### Timecode Outputs
-- 
-- - **Art-Net TimeCode** — broadcasts SMPTE TC over UDP (port 6454); unicast or broadcast destination; configurable IP
-- - **MIDI Timecode (MTC)** — JSFX-native quarter-frame generator at sample-accurate offsets; no external MIDI library required
-- - **OSC** — broadcasts SMPTE TC as raw OSC (`/tc ,iiiii H M S F type`) at ~30 fps; configurable destination IP, port, and OSC address
-- - **LTC audio generator** — encodes timecode to LTC audio with rise-time filtering per SMPTE 12M spec; configurable output level
-- - **Bake LTC from regions** — standalone tool generates offline LTC WAV files from project regions; per-region TC start, FPS, and selection; configurable output level, track, and filename template
-- 
-- ### Features
-- 
-- - **TC Offset** — user-configurable HH:MM:SS:FF offset applied inside the JSFX before all outputs; supports add/subtract, drop-frame wrap-around, and 24-hour wrap; persisted across sessions
-- - **Unified Timecode Converter JSFX** — single `reatc_tc.jsfx` plugin handles all TC sources and outputs with interactive @gfx UI
-- - **Network sync status** — Art-Net and OSC indicators show packet counts and daemon health (green/red/orange)
-- - **JSFX detection warning** — Lua script shows orange warning when the JSFX is not loaded or has Script Output disabled
-- - **C++ extension** — registers custom REAPER action IDs (`_REATC_MAIN`, `_REATC_BAKE_LTC`, `_REATC_TOGGLE_ARTNET`, `_REATC_TOGGLE_OSC`) for OSC/MIDI controller automation; prints load confirmation with assigned command IDs to REAPER console
-- - **All standard frame rates** — 24fps (Film), 25fps (EBU/PAL), 29.97fps Drop Frame, 30fps (SMPTE)
-- - **Dark UI** — Lua window and JSFX share a unified dark visual style; TC display and text scale proportionally when resizing
-- - **Cross-platform** — macOS (10.15+) and Windows (10+); Python 3 standard library only
-- - **ReaPack compatible** — install via package manager; ReaImGui auto-installed as dependency
-- - Named `GMEM_*` constants in Lua matching JSFX gmem layout
-- - Settings key constants to prevent typo bugs in load/save
-- - Daemon pre-start on enable (eliminates first-packet latency)
-- - Output throttle now matches active framerate instead of fixed 30Hz
-- - Python unit tests for Art-Net/OSC packet construction, LTC frame building, TC advance, drop-frame logic, and build system
-- - Lua syntax validation (`luac -p`) and pytest runner in CI
-- - Manual installation, troubleshooting, and ReaPack restart step in README
-- - LDoc annotations on all Lua public functions
-- - Type hints and expanded docstrings on all Python functions
-- - Doxygen comments on C++ extension with ExtState IPC contract
-- - JSFX section headers and MTC mid-cycle rollover documentation
-- - Architecture diagram updated with C++ extension, ExtState IPC, and reatc_ltcgen.py
-- - `make test` and `make docs` Makefile targets
-- - `config.ld` for LDoc generation
-- - `REPORT.md` code review report (23 findings, all resolved)
-- 
-- ### Fixed
-- 
-- - C++ extension actions appeared in Actions list but did nothing when triggered — added `hookcommand2`/`toggleaction` registration error checking and diagnostic logging
-- - C++ extension `run_script()` now logs the exact path tried when a Lua script is not found
-- - ReaPack install path doubled (`Scripts/ReaTC/ReaTC/`) — category renamed from `ReaTC/` to `Timecode/`; C++ extension paths updated to match
-- - JSFX LTC decoder: fixed bpm_period seed from full-cell to half-cell width — 25fps now locks immediately at any level
-- - JSFX LTC encoder: added play-start transition reset and frame rebuild on rate change
-- - Python daemons now validate TC ranges (0-23h, 0-59m, 0-59s, 0-29f) and log malformed input to stderr
-- - Daemon write failure now retries 3 times with backoff before disabling output (was: immediate disable)
-- - `os.execute` return values checked in Bake LTC from Regions (mkdir and generation)
-- - LTC generator CLI amplitude clamped to valid int16 range (1–32767)
-- - OSC address validated to start with `/` per OSC spec
-- - Build scripts use explicit `encoding="utf-8"` for Windows compatibility
-- 
-- ### Changed
-- 
-- - CI: merged `build-extension` job into `validate` in check.yml (saves one VM boot)
-- - CI: lua syntax check now uses mise-installed lua instead of apt
-- - CI: added pip cache for pytest, mise cache for release.yml, gem cache for reapack-index
-- - CI: pandoc installed via `pandoc/actions/setup@v1` instead of apt

--- ReaTC — https://github.com/paskateknikko/ReaTC
-- Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
--
--- Entry point for ReaTC. Initializes submodules, attaches to JSFX gmem,
-- and runs a deferred main loop that: reads TC from gmem, polls for
-- ExtState toggle commands from the C++ extension, and sends network output.
-- TC sources and outputs are configured in the ReaTC Timecode Converter JSFX.

if not reaper.ImGui_GetBuiltinPath then
  reaper.MB(
    'ReaImGui not installed.\n\nInstall it from ReaPack (ReaTeam Extensions → ReaImGui).',
    'ReaTC', 0)
  return
end

local script_path

do
  local info = debug.getinfo(1, "S")
  script_path = info.source:match("@(.+[\\/])") or ""
end

local core    = dofile(script_path .. "reatc_core.lua")
local outputs = dofile(script_path .. "reatc_outputs.lua")(core)
local ui      = dofile(script_path .. "reatc_ui.lua")(core, outputs)

local function init()
  core.load_settings()

  -- Attach to JSFX shared memory
  reaper.gmem_attach("ReaTC_LTC")

  core.state.python_bin = core.find_python()
  if not core.state.python_bin then
    core.state.python_error = "Python 3 not found"
    reaper.MB(
      "Python 3 not found.\n\n" ..
      "macOS: Python 3 is pre-installed.\n" ..
      "Windows: Install from Microsoft Store or https://python.org",
      "ReaTC — Python Required", 0)
  end

  ui.init()

  -- Pre-start daemons if outputs were enabled from saved settings
  outputs.prestart_daemons()
end

local function loop()
  if not ui.draw_ui() then
    -- Window closed — clean up
    outputs.stop_artnet_daemon()
    outputs.stop_osc_daemon()
    core.save_settings()
    return  -- do NOT defer again
  end

  -- Signal to JSFX that Lua script is alive
  reaper.gmem_write(core.GMEM_SCRIPT_ALIVE,
    (reaper.gmem_read(core.GMEM_SCRIPT_ALIVE) + 1) % 65536)

  -- Write TC offset to gmem for JSFX
  reaper.gmem_write(core.GMEM_TC_OFFSET_H, core.state.tc_offset_h)
  reaper.gmem_write(core.GMEM_TC_OFFSET_M, core.state.tc_offset_m)
  reaper.gmem_write(core.GMEM_TC_OFFSET_S, core.state.tc_offset_s)
  reaper.gmem_write(core.GMEM_TC_OFFSET_F, core.state.tc_offset_f)
  reaper.gmem_write(core.GMEM_TC_OFFSET_SIGN, core.state.tc_offset_negative and 1 or 0)

  -- Read active TC from JSFX via gmem
  core.update_tc_from_gmem()

  -- Poll for toggle commands from C++ extension (OSC/controller IPC)
  local s = core.state
  if reaper.GetExtState("ReaTC_CMD", "toggle_artnet") == "1" then
    reaper.DeleteExtState("ReaTC_CMD", "toggle_artnet", false)
    s.artnet_enabled = not s.artnet_enabled
    if s.artnet_enabled then s.packets_sent = 0 else outputs.stop_artnet_daemon() end
    core.save_settings()
  end
  if reaper.GetExtState("ReaTC_CMD", "toggle_osc") == "1" then
    reaper.DeleteExtState("ReaTC_CMD", "toggle_osc", false)
    s.osc_enabled = not s.osc_enabled
    if s.osc_enabled then s.osc_packets_sent = 0 else outputs.stop_osc_daemon() end
    core.save_settings()
  end
  -- Publish state for C++ toggleaction callback
  reaper.SetExtState("ReaTC_STATE", "artnet", s.artnet_enabled and "1" or "0", false)
  reaper.SetExtState("ReaTC_STATE", "osc",    s.osc_enabled    and "1" or "0", false)

  -- Send to network outputs
  outputs.send_artnet()
  outputs.send_osc()

  reaper.defer(loop)
end

init()
loop()
