-- ReaTC — https://github.com/<org>/ReaTC
-- Copyright (c) 2025 Tuukka Aimasmaki. MIT License — see LICENSE.
--
-- Sends Art-Net TimeCode and MIDI Timecode from REAPER.
-- Decodes LTC audio from a track via REAPER audio accessor.
--
-- Requirements:
-- - REAPER 6.0+
-- - Python 3 (pre-installed on macOS; Windows Store / python.org on Windows)
-- - python-rtmidi  (auto-installed on first MTC enable, MIT license)
--
-- No REAPER extensions required (no ReaImGui, no SWS, no JSFX).

local script_path

do
  local info = debug.getinfo(1, "S")
  script_path = info.source:match("@(.+[\\/])") or ""
end

local core = dofile(script_path .. "reatc_core.lua")
local ltc = dofile(script_path .. "reatc_ltc.lua")(core)
local outputs = dofile(script_path .. "reatc_outputs.lua")(core)
local ui = dofile(script_path .. "reatc_ui.lua")(core, outputs, ltc)

local state = core.state

local function init()
  core.load_settings()

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

  gfx.init("ReaTC v" .. core.VERSION, core.MIN_WIN_W, core.MIN_WIN_H)
  gfx.setfont(1, "Arial", 13, 0)
end

local function loop()
  local c = gfx.getchar()
  if c == -1 then
    -- Window closed → clean up
    ltc.destroy_accessor()
    outputs.stop_mtc_daemon()
    core.save_settings()
    return  -- do NOT defer again
  end

  ui.handle_key(c)
  ui.update_mouse()
  core.update_transport_tc()

  -- LTC decode
  if state.ltc_enabled and state.ltc_track then
    local playing = (reaper.GetPlayState() & 1) == 1
    if playing then
      ltc.decode_ltc_chunk()
      state.was_playing = true
      -- Invalidate TC if no valid sync detected for 0.5 seconds (likely no signal)
      if state.tc_valid and
         reaper.time_precise() - state.last_valid_time > 0.5 then
        state.tc_valid = false
      end
    else
      if state.was_playing then
        ltc.destroy_accessor()  -- reset; will be re-created on next play
      end
      state.was_playing = false
      -- When stopped, invalidate TC after 1 second of no signal
      if state.tc_valid and
         reaper.time_precise() - state.last_valid_time > 1.0 then
        state.tc_valid = false
      end
    end
  else
    state.tc_valid = false
  end

  outputs.send_artnet()
  outputs.send_mtc()
  ui.draw_ui()
  gfx.update()

  reaper.defer(loop)
end

init()
loop()
