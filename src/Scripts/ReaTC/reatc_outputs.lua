--- ReaTC — https://github.com/paskateknikko/ReaTC
-- Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
--
--- ReaTC outputs: Art-Net and OSC timecode via the ReaTC C++ extension.
-- Each defer cycle (throttled to the active framerate) the current TC is
-- handed to `reaper.ReaTC_SendArtNetTC` / `reaper.ReaTC_SendOSCTC`, which
-- build the packet and send it on a cached UDP socket inside REAPER.
-- No Python, no subprocesses: settings changes take effect on the next packet.
-- @module reatc_outputs
-- @noindex
-- @version {{VERSION}}

return function(core)
  local M = {}
  local s = core.state

  M.EXT_MISSING = "ReaTC extension not loaded \u{2014} reinstall ReaTC and restart REAPER"

  --- Record the result of one send call into the per-output state.
  -- @param ret number packets sent (>= 1) or -1 on error
  -- @param kind string "artnet" or "osc"
  -- @return boolean true if at least one packet was sent
  local function record(ret, kind)
    local msg = reaper.ReaTC_GetLastError(kind)
    if msg == "" then msg = nil end
    if ret and ret > 0 then
      return true, nil, msg            -- ok, no error, optional bind warning
    end
    return false, msg or "Send failed", nil
  end

  --- True if it is time to send another packet (framerate throttle).
  local function due(last_key)
    local fps = core.FPS_VAL[s.framerate_type + 1] or 30
    local now = reaper.time_precise()
    if now - s[last_key] < 1 / fps then return false end
    s[last_key] = now
    return true
  end

  --- Send current TC as Art-Net TimeCode (throttled to framerate).
  function M.send_artnet()
    if not s.artnet_enabled then return end
    if not core.ext_loaded() then s.artnet_error = M.EXT_MISSING; return end
    if not s.tc_valid then return end
    if not due("last_artnet_time") then return end

    local h, m, sec, f = core.get_active_tc()
    local src = core.resolve_bind_ip(s.artnet_preferred_ip, s.artnet_preferred_iface) or ""
    local ret = reaper.ReaTC_SendArtNetTC(s.dest_ip, src, math.floor(s.artnet_stream_id),
                                          h, m, sec, f, s.framerate_type)
    local ok, err, warn = record(ret, "artnet")
    s.artnet_error, s.artnet_warning = err, warn
    if ok then s.packets_sent = s.packets_sent + 1 end
  end

  --- Send current TC as an OSC message (throttled to framerate).
  function M.send_osc()
    if not s.osc_enabled then return end
    if not core.ext_loaded() then s.osc_error = M.EXT_MISSING; return end
    if not s.tc_valid then return end
    if not due("last_osc_time") then return end

    local h, m, sec, f = core.get_active_tc()
    local src = core.resolve_bind_ip(s.osc_preferred_ip, s.osc_preferred_iface) or ""
    local ret = reaper.ReaTC_SendOSCTC(s.osc_ip, math.floor(s.osc_port), s.osc_address, src,
                                       h, m, sec, f, s.framerate_type)
    local ok, err, warn = record(ret, "osc")
    s.osc_error, s.osc_warning = err, warn
    if ok then s.osc_packets_sent = s.osc_packets_sent + 1 end
  end

  --- Reset per-output status when an output is switched on or off.
  function M.reset_artnet()
    s.packets_sent, s.artnet_error, s.artnet_warning = 0, nil, nil
  end
  function M.reset_osc()
    s.osc_packets_sent, s.osc_error, s.osc_warning = 0, nil, nil
  end

  return M
end
