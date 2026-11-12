--- ReaTC — https://github.com/paskateknikko/ReaTC
-- Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
--
--- ReaTC outputs: Art-Net and OSC timecode via the ReaTC C++ extension.
-- Each defer cycle hands the extension the current TC (with when the frame
-- started and whether TC is running) and the output settings. The extension
-- sends the packets from its own thread, one per frame on the frame
-- boundary, so output does not depend on the ~30 Hz defer rate.
-- No Python, no subprocesses: settings changes take effect on the next frame.
-- @module reatc_outputs
-- @noindex
-- @version {{VERSION}}

return function(core)
  local M = {}
  local s = core.state

  M.EXT_MISSING = "ReaTC extension not loaded \u{2014} reinstall ReaTC and restart REAPER"

  --- Non-empty string or nil.
  local function nonempty(str)
    if str == nil or str == "" then return nil end
    return str
  end

  --- Push the current TC and output settings to the extension and read back
  -- packet counts, errors and bind warnings. Call once per defer cycle:
  -- the extension stops sending if updates stop for 1 s.
  function M.update()
    if not core.ext_loaded() then
      s.artnet_error = s.artnet_enabled and M.EXT_MISSING or nil
      s.osc_error = s.osc_enabled and M.EXT_MISSING or nil
      return
    end

    local h, m, sec, f = core.get_active_tc()
    local age = 0
    if s.tc_running then
      age = math.max(0, reaper.time_precise() - s.tc_frame_time)
    end
    reaper.ReaTC_SetTC(s.tc_valid, h, m, sec, f, s.framerate_type, s.tc_running, age)

    local art_src = s.artnet_enabled
      and core.resolve_bind_ip(s.artnet_preferred_ip, s.artnet_preferred_iface) or ""
    reaper.ReaTC_SetArtNetOutput(s.artnet_enabled, s.dest_ip, art_src,
                                 math.floor(s.artnet_stream_id))

    local osc_src = s.osc_enabled
      and core.resolve_bind_ip(s.osc_preferred_ip, s.osc_preferred_iface) or ""
    reaper.ReaTC_SetOSCOutput(s.osc_enabled, s.osc_ip, math.floor(s.osc_port),
                              s.osc_address, osc_src)

    s.packets_sent = reaper.ReaTC_GetPacketCount("artnet")
    s.artnet_error = nonempty(reaper.ReaTC_GetLastError("artnet"))
    s.artnet_warning = nonempty(reaper.ReaTC_GetLastWarning("artnet"))
    s.osc_packets_sent = reaper.ReaTC_GetPacketCount("osc")
    s.osc_error = nonempty(reaper.ReaTC_GetLastError("osc"))
    s.osc_warning = nonempty(reaper.ReaTC_GetLastWarning("osc"))
  end

  --- Stop all network output (script exit).
  function M.shutdown()
    if not core.ext_loaded() then return end
    reaper.ReaTC_SetTC(false, 0, 0, 0, 0, 0, false, 0)
    reaper.ReaTC_SetArtNetOutput(false, "", "", 0)
    reaper.ReaTC_SetOSCOutput(false, "", 0, "", "")
  end

  --- Clear per-output status when an output is switched on or off.
  -- (The extension resets its packet count when the output is re-enabled.)
  function M.reset_artnet()
    s.packets_sent, s.artnet_error, s.artnet_warning = 0, nil, nil
  end
  function M.reset_osc()
    s.osc_packets_sent, s.osc_error, s.osc_warning = 0, nil, nil
  end

  return M
end
