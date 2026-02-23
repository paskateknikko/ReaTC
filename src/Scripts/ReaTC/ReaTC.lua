-- @description Art-Net and MIDI Timecode sender for REAPER
-- @author Tuukka Aimasmäki
-- @version {{VERSION}}
-- @link https://github.com/paskateknikko/ReaTC
-- @link reapack https://github.com/ReaTeam/Extensions/raw/master/index.xml ReaImGui
-- @provides
--   [main] ReaTC.lua
--   ReaTC/reatc_core.lua
--   ReaTC/reatc_ltc.lua
--   ReaTC/reatc_outputs.lua
--   ReaTC/reatc_ui.lua
--   ReaTC/reatc_artnet.py
--   ReaTC/reatc_udp.py
--   ReaTC/reatc_mtc.py
--   ReaTC/reatc_osc.py
--   [effect] ../Effects/ReaTC/reatc_ltc.jsfx
-- @about
--   # ReaTC
--
--   TESTITESTITESTI
--   Sends **Art-Net TimeCode** and **MIDI Timecode** from REAPER.
--   Decodes incoming LTC audio via a bundled JSFX plugin.
--
--   ## Features
--   - Art-Net TimeCode broadcast (configurable destination IP)
--   - MIDI Timecode (MTC) output via virtual or physical MIDI port
--   - LTC audio decoder (JSFX, real-time, no REAPER extensions required)
--   - 24fps (Film), 25fps (EBU), 29.97 DF, 30fps (SMPTE)
--   - Fallback to REAPER timeline when no LTC signal
--
--   ## Requirements
--   - REAPER 6.0+
--   - **ReaImGui** (installed automatically via ReaPack dependency)
--   - Python 3 (pre-installed on macOS; Windows Store / python.org on Windows)
--   - `python-rtmidi` (optional, for MTC — auto-installed on first use)
--
--   ## Links
--   - [GitHub](https://github.com/paskateknikko/ReaTC)

-- ReaTC — https://github.com/paskateknikko/ReaTC
-- Copyright (c) 2025 Tuukka Aimasmaki. MIT License — see LICENSE.
--
-- Sends Art-Net TimeCode and MIDI Timecode from REAPER.
-- Decodes LTC audio from a track via a JSFX plugin (reatc_ltc.jsfx).

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
local ltc     = dofile(script_path .. "reatc_ltc.lua")(core)
local outputs = dofile(script_path .. "reatc_outputs.lua")(core)
local ui      = dofile(script_path .. "reatc_ui.lua")(core, outputs, ltc)

local state = core.state

local function init()
  core.load_settings()

  -- Attach to JSFX shared memory for script-alive signalling
  reaper.gmem_attach("ReaTC_LTC")

  state.python_bin = core.find_python()
  if not state.python_bin then
    state.python_error = "Python 3 not found"
    reaper.MB(
      "Python 3 not found.\n\n" ..
      "macOS: Python 3 is pre-installed.\n" ..
      "Windows: Install from Microsoft Store or https://python.org",
      "ReaTC — Python Required", 0)
  end

  if state.ltc_enabled and state.ltc_track_idx ~= nil then
    state.ltc_track = reaper.GetTrack(0, state.ltc_track_idx)
  end

  if state.mtc_enabled then
    if core.check_rtmidi() then
      state.mtc_ports = core.list_midi_ports()
      outputs.start_mtc_daemon()
    else
      state.mtc_enabled = false
      state.mtc_error   = "python-rtmidi missing — re-enable MTC to install"
      core.save_settings()
    end
  end

  ui.init()
end

local function loop()
  if not ui.draw_ui() then
    -- Window closed — clean up
    ltc.destroy_accessor()
    outputs.stop_mtc_daemon()
    outputs.stop_artnet_daemon()
    outputs.stop_osc_daemon()
    core.save_settings()
    return  -- do NOT defer again
  end

  -- Signal to JSFX that Lua script is alive (gmem index 8)
  reaper.gmem_write(8, (reaper.gmem_read(8) + 1) % 65536)

  core.update_transport_tc()

  if state.ltc_enabled and state.ltc_track then
    ltc.update_jsfx()
  else
    state.tc_valid = false
  end

  outputs.send_artnet()
  outputs.send_osc()
  outputs.send_mtc()

  reaper.defer(loop)
end

init()
loop()
