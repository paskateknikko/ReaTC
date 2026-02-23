-- ReaTC outputs: MTC daemon and Art-Net sender
-- @noindex
-- @version {{VERSION}}

return function(core)
  local M = {}
  local s = core.state

  function M.start_mtc_daemon()
    if s.mtc_proc then return true end
    if not s.python_bin then
      s.mtc_error = "Python not found"; return false
    end
    local q = core.is_win and ('"' .. s.python_bin .. '"') or s.python_bin
    local cmd
    if s.mtc_port ~= "" then
      cmd = q .. ' "' .. core.py_mtc .. '" "' .. s.mtc_port .. '" ' .. core.dev_null
    else
      cmd = q .. ' "' .. core.py_mtc .. '" ' .. core.dev_null
    end
    s.mtc_proc = io.popen(cmd, "w")
    if not s.mtc_proc then
      s.mtc_error = "Failed to start MTC daemon"; return false
    end
    s.mtc_error = nil
    return true
  end

  function M.stop_mtc_daemon()
    if s.mtc_proc then
      pcall(function() s.mtc_proc:close() end)
      s.mtc_proc = nil
    end
  end

  function M.send_mtc()
    if not s.mtc_enabled or not s.mtc_proc then return end
    local now = reaper.time_precise()
    if now - s.last_mtc_time < 0.033 then return end
    s.last_mtc_time = now

    local play = (reaper.GetPlayState() & 1) == 1
    local h, m, sec, f = core.get_active_tc()
    local t = s.framerate_type

    local ok = pcall(function()
      s.mtc_proc:write(string.format("%s %d %d %d %d %d\n",
        play and "play" or "stop", h, m, sec, f, t))
      s.mtc_proc:flush()
    end)
    if not ok then
      s.mtc_error = "Daemon write failed"
      M.stop_mtc_daemon()
      s.mtc_enabled = false
    end
  end

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
    return true
  end

  function M.stop_osc_daemon()
    if s.osc_proc then
      pcall(function() s.osc_proc:close() end)
      s.osc_proc = nil
    end
  end

  function M.send_osc()
    if not s.osc_enabled or not s.python_bin then return end
    local play = (reaper.GetPlayState() & 1) == 1
    if not play then return end
    local now = reaper.time_precise()
    if now - s.last_osc_time < 1 / 30 then return end
    s.last_osc_time = now

    -- Start daemon on first send
    if not s.osc_proc then
      if not M.start_osc_daemon() then return end
    end

    local h, m, sec, f = core.get_active_tc()
    local t = s.framerate_type

    local ok = pcall(function()
      s.osc_proc:write(string.format("%d %d %d %d %d\n", h, m, sec, f, t))
      s.osc_proc:flush()
    end)
    if not ok then
      s.osc_error = "Daemon write failed"
      M.stop_osc_daemon()
      s.osc_enabled = false
    else
      s.osc_error = nil
    end
  end

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
    return true
  end

  function M.stop_artnet_daemon()
    if s.artnet_proc then
      pcall(function() s.artnet_proc:close() end)
      s.artnet_proc = nil
    end
  end

  function M.send_artnet()
    if not s.artnet_enabled or not s.python_bin then return end
    local play = (reaper.GetPlayState() & 1) == 1
    if not play then return end
    local now = reaper.time_precise()
    if now - s.last_artnet_time < 1 / 30 then return end
    s.last_artnet_time = now

    -- Start daemon on first send
    if not s.artnet_proc then
      if not M.start_artnet_daemon() then return end
    end

    local h, m, sec, f = core.get_active_tc()
    local t = s.framerate_type

    local ok = pcall(function()
      s.artnet_proc:write(string.format("%d %d %d %d %d\n", h, m, sec, f, t))
      s.artnet_proc:flush()
    end)
    if not ok then
      s.artnet_error = "Daemon write failed"
      M.stop_artnet_daemon()
      s.artnet_enabled = false
    else
      s.packets_sent = s.packets_sent + 1
      s.artnet_error = nil
    end
  end

  return M
end
