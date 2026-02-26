--- ReaTC — https://github.com/paskateknikko/ReaTC
-- Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
--
--- ReaTC outputs: manages persistent Python daemon subprocesses for Art-Net and OSC.
-- Each daemon is an `io.popen("w")` process that reads TC lines from stdin and sends
-- UDP packets. Daemons are started lazily (or pre-started via `prestart_daemons`),
-- throttled to match the active framerate, and automatically restarted up to 3 times
-- on write failure before disabling the output.
-- @module reatc_outputs
-- @noindex
-- @version {{VERSION}}

return function(core)
  local M = {}
  local s = core.state

  -- Retry configuration
  local MAX_RETRIES = 3
  local RETRY_BACKOFF = { 0.5, 1.0, 2.0 }  -- seconds between retries

  -- Per-daemon retry state
  s.osc_retries    = 0
  s.osc_retry_at   = 0
  s.artnet_retries = 0
  s.artnet_retry_at = 0

  -- ── OSC daemon ───────────────────────────────────────────────────────────

  --- Launch the OSC Python daemon subprocess.
  -- @return boolean true if daemon is running
  function M.start_osc_daemon()
    if s.osc_proc then return true end
    if not s.python_bin then
      s.osc_error = "Python not found"; return false
    end
    local q = core.is_win and ('"' .. s.python_bin .. '"') or s.python_bin
    local cmd = q .. ' "' .. core.py_osc .. '" "' .. s.osc_ip .. '" '
                .. s.osc_port .. ' "' .. s.osc_address .. '" ' .. core.dev_null
    s.osc_proc = io.popen(cmd, "w")
    if not s.osc_proc then
      s.osc_error = "Failed to start OSC daemon"; return false
    end
    s.osc_error = nil
    s.osc_retries = 0
    return true
  end

  --- Stop the OSC daemon subprocess gracefully.
  function M.stop_osc_daemon()
    if s.osc_proc then
      pcall(function() s.osc_proc:close() end)
      s.osc_proc = nil
    end
  end

  --- Send current TC to the OSC daemon (throttled, with retry on failure).
  function M.send_osc()
    if not s.osc_enabled or not s.python_bin then return end
    if not s.tc_valid then return end

    -- Throttle to match framerate
    local fps = core.FPS_VAL[s.framerate_type + 1] or 30
    local now = reaper.time_precise()
    if now - s.last_osc_time < 1 / fps then return end
    s.last_osc_time = now

    -- Retry backoff: wait before attempting restart
    if not s.osc_proc and s.osc_retries > 0 then
      if now < s.osc_retry_at then return end
    end

    -- Start daemon on first send (or restart after failure)
    if not s.osc_proc then
      if not M.start_osc_daemon() then return end
    end

    -- stdin protocol: "H M S F fps_type\n"
    local h, m, sec, f = core.get_active_tc()
    local t = s.framerate_type

    local ok = pcall(function()
      s.osc_proc:write(string.format("%d %d %d %d %d\n", h, m, sec, f, t))
      s.osc_proc:flush()
    end)
    if not ok then
      M.stop_osc_daemon()
      s.osc_retries = s.osc_retries + 1
      if s.osc_retries > MAX_RETRIES then
        s.osc_error = "Daemon failed after " .. MAX_RETRIES .. " retries"
        s.osc_enabled = false
      else
        s.osc_error = "Daemon write failed (retry " .. s.osc_retries .. "/" .. MAX_RETRIES .. ")"
        s.osc_retry_at = now + (RETRY_BACKOFF[s.osc_retries] or 2.0)
      end
    else
      s.osc_packets_sent = s.osc_packets_sent + 1
      s.osc_error = nil
      s.osc_retries = 0
    end
  end

  -- ── Art-Net daemon ───────────────────────────────────────────────────────

  --- Launch the Art-Net Python daemon subprocess.
  -- @return boolean true if daemon is running
  function M.start_artnet_daemon()
    if s.artnet_proc then return true end
    if not s.python_bin then
      s.artnet_error = "Python not found"; return false
    end
    local q = core.is_win and ('"' .. s.python_bin .. '"') or s.python_bin
    local cmd = q .. ' "' .. core.py_artnet .. '" "' .. s.dest_ip .. '" ' .. core.dev_null
    s.artnet_proc = io.popen(cmd, "w")
    if not s.artnet_proc then
      s.artnet_error = "Failed to start Art-Net daemon"; return false
    end
    s.artnet_error = nil
    s.artnet_retries = 0
    return true
  end

  --- Stop the Art-Net daemon subprocess gracefully.
  function M.stop_artnet_daemon()
    if s.artnet_proc then
      pcall(function() s.artnet_proc:close() end)
      s.artnet_proc = nil
    end
  end

  --- Send current TC to the Art-Net daemon (throttled, with retry on failure).
  function M.send_artnet()
    if not s.artnet_enabled or not s.python_bin then return end
    if not s.tc_valid then return end

    -- Throttle to match framerate
    local fps = core.FPS_VAL[s.framerate_type + 1] or 30
    local now = reaper.time_precise()
    if now - s.last_artnet_time < 1 / fps then return end
    s.last_artnet_time = now

    -- Retry backoff: wait before attempting restart
    if not s.artnet_proc and s.artnet_retries > 0 then
      if now < s.artnet_retry_at then return end
    end

    -- Start daemon on first send (or restart after failure)
    if not s.artnet_proc then
      if not M.start_artnet_daemon() then return end
    end

    -- stdin protocol: "H M S F fps_type\n"
    local h, m, sec, f = core.get_active_tc()
    local t = s.framerate_type

    local ok = pcall(function()
      s.artnet_proc:write(string.format("%d %d %d %d %d\n", h, m, sec, f, t))
      s.artnet_proc:flush()
    end)
    if not ok then
      M.stop_artnet_daemon()
      s.artnet_retries = s.artnet_retries + 1
      if s.artnet_retries > MAX_RETRIES then
        s.artnet_error = "Daemon failed after " .. MAX_RETRIES .. " retries"
        s.artnet_enabled = false
      else
        s.artnet_error = "Daemon write failed (retry " .. s.artnet_retries .. "/" .. MAX_RETRIES .. ")"
        s.artnet_retry_at = now + (RETRY_BACKOFF[s.artnet_retries] or 2.0)
      end
    else
      s.packets_sent = s.packets_sent + 1
      s.artnet_error = nil
      s.artnet_retries = 0
    end
  end

  -- ── Pre-start ────────────────────────────────────────────────────────────

  --- Pre-start enabled daemons to avoid first-packet latency.
  -- Called once during init after settings are loaded.
  function M.prestart_daemons()
    if s.artnet_enabled and not s.artnet_proc and s.python_bin then
      M.start_artnet_daemon()
    end
    if s.osc_enabled and not s.osc_proc and s.python_bin then
      M.start_osc_daemon()
    end
  end

  return M
end
