-- @description Art-Net and MIDI Timecode sender for REAPER
-- @author Tuukka Aimasmäki
-- @version {{VERSION}}
-- @link https://github.com/paskateknikko/ReaTC
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
--   {{CHANGELOG}}

-- ReaTC — https://github.com/paskateknikko/ReaTC
-- Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
--
-- Sends Art-Net TimeCode and OSC from REAPER.
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
end

local function loop()
  if not ui.draw_ui() then
    -- Window closed — clean up
    outputs.stop_artnet_daemon()
    outputs.stop_osc_daemon()
    core.save_settings()
    return  -- do NOT defer again
  end

  -- Signal to JSFX that Lua script is alive (gmem index 8)
  reaper.gmem_write(8, (reaper.gmem_read(8) + 1) % 65536)

  -- Write TC offset to gmem for JSFX (indices 20-24)
  reaper.gmem_write(20, core.state.tc_offset_h)
  reaper.gmem_write(21, core.state.tc_offset_m)
  reaper.gmem_write(22, core.state.tc_offset_s)
  reaper.gmem_write(23, core.state.tc_offset_f)
  reaper.gmem_write(24, core.state.tc_offset_negative and 1 or 0)

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
