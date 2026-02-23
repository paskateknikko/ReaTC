-- ReaTC UI — ReaImGui implementation
-- @noindex
-- @version {{VERSION}}

return function(core, outputs, ltc)
  local M = {}
  local s = core.state

  -- Load ReaImGui
  package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
  local ImGui = require 'imgui' '0.9'

  local ctx, font_tc

  -- Colors: 0xRRGGBBAA
  local C = {
    text   = 0xE5E5E5FF,
    green  = 0x33D95AFF,
    orange = 0xF2A626FF,
    red    = 0xE14040FF,
    dim    = 0x80808CFF,
    blue   = 0x5AA4F2FF,
  }

  function M.init()
    ctx    = ImGui.CreateContext('ReaTC')
    font_tc = ImGui.CreateFont('Courier New', 72, ImGui.FontFlags_Bold)
    ImGui.Attach(ctx, font_tc)
  end

  local function trunc(str, n)
    if #str <= n then return str end
    return str:sub(1, n - 3) .. "..."
  end

  -- ── Main view ──────────────────────────────────────────────────────────────

  local function draw_main()
    local h, m, sec, f, source = core.get_active_tc()
    local tc_str       = string.format("%02d:%02d:%02d:%02d", h, m, sec, f)
    local is_ltc_locked = (source == "LTC")

    -- Large TC display
    ImGui.PushFont(ctx, font_tc)
    local tc_color = is_ltc_locked and C.green
                     or ((s.artnet_enabled or s.mtc_enabled) and C.green or C.dim)
    ImGui.TextColored(ctx, tc_color, tc_str)
    ImGui.PopFont(ctx)

    -- Status line
    local sl, sl_color
    if s.ltc_enabled and s.ltc_track ~= nil then
      if is_ltc_locked then
        sl       = "LTC LOCKED   " .. core.FR_NAMES[s.framerate_type + 1]
        sl_color = C.green
      else
        sl       = (s.ltc_fallback
                    and "SEARCHING (Timeline fallback)   "
                    or  "SEARCHING (holding)   ")
                   .. core.FR_NAMES[s.framerate_type + 1]
        sl_color = C.orange
      end
    else
      if s.artnet_enabled or s.mtc_enabled then
        sl       = string.format("Timeline   %s", core.FR_NAMES[s.framerate_type + 1])
        sl_color = C.green
      else
        sl       = "Timeline   " .. core.FR_NAMES[s.framerate_type + 1] .. "  (idle)"
        sl_color = C.dim
      end
    end
    ImGui.TextColored(ctx, sl_color, sl)

    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, 'Settings') then
      s.show_settings = true
    end
    ImGui.Spacing(ctx)
    ImGui.TextColored(ctx, C.dim, "v" .. core.VERSION)
  end

  -- ── Settings view ──────────────────────────────────────────────────────────

  local function draw_settings()
    -- Header: mini TC + Close button on same row
    local h, m, sec, f, source = core.get_active_tc()
    local tc_str        = string.format("%02d:%02d:%02d:%02d", h, m, sec, f)
    local is_ltc_locked = (source == "LTC")
    local tc_color      = is_ltc_locked and C.green
                          or ((s.artnet_enabled or s.mtc_enabled) and C.green or C.dim)
    ImGui.TextColored(ctx, tc_color, tc_str)
    ImGui.SameLine(ctx)
    ImGui.SetCursorPosX(ctx, ImGui.GetWindowWidth(ctx) - 70)
    if ImGui.Button(ctx, 'Close') then
      s.show_settings = false
    end

    -- ── Art-Net ──────────────────────────────────────────────────────────────
    ImGui.SeparatorText(ctx, 'Art-Net Output')

    local an_changed, an_val = ImGui.Checkbox(ctx, 'Enable##artnet', s.artnet_enabled)
    if an_changed then
      s.artnet_enabled = an_val
      if an_val then s.packets_sent = 0 end
      core.save_settings()
    end

    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 180)
    local ip_changed, new_ip = ImGui.InputText(ctx, 'Destination IP', s.dest_ip)
    if ip_changed then
      if core.is_valid_ipv4(new_ip) then
        s.dest_ip = new_ip
        core.save_settings()
        -- Restart daemon with new IP
        if s.artnet_enabled then
          M.stop_artnet_daemon()
        end
      elseif new_ip ~= "" then
        -- Show error: invalid IP format
        ImGui.TextColored(ctx, C.red, "Invalid IP: must be aaa.bbb.ccc.ddd (0-255 each)")
      end
    end

    if s.artnet_error then
      ImGui.TextColored(ctx, C.red, "Error: " .. trunc(s.artnet_error, 60))
    elseif s.python_bin then
      ImGui.TextColored(ctx, C.dim, "Python: " .. trunc(s.python_bin, 50))
    else
      ImGui.TextColored(ctx, C.red, "Python 3 not found!")
    end

    -- ── MTC ──────────────────────────────────────────────────────────────────
    ImGui.SeparatorText(ctx, 'MTC Output')

    local mtc_changed, mtc_val = ImGui.Checkbox(ctx, 'Enable MTC', s.mtc_enabled)
    if mtc_changed then
      if mtc_val then   -- turning on
        if core.check_rtmidi() or core.try_install_rtmidi() then
          s.mtc_enabled = true
          s.mtc_error   = nil
          if not s.mtc_ports then s.mtc_ports = core.list_midi_ports() end
          outputs.start_mtc_daemon()
        end
      else              -- turning off
        s.mtc_enabled = false
        outputs.stop_mtc_daemon()
        s.mtc_error = nil
      end
      core.save_settings()
    end

    if s.mtc_enabled then
      local ports     = s.mtc_ports or {}
      local port_names = {}
      local cur_idx   = 0
      for i, p in ipairs(ports) do
        port_names[i] = (p.index == -1) and "Virtual Port" or p.name
        if (s.mtc_port == "" and p.index == -1) or
           (s.mtc_port ~= "" and p.name == s.mtc_port) then
          cur_idx = i - 1   -- 0-based for ImGui.Combo
        end
      end
      local port_items = table.concat(port_names, '\0') .. '\0'
      ImGui.SetNextItemWidth(ctx, 280)
      local port_changed, new_idx = ImGui.Combo(ctx, 'Port##mtc', cur_idx, port_items)
      if port_changed then
        local np = ports[new_idx + 1]
        if np then
          s.mtc_port = (np.index == -1) and "" or np.name
          outputs.stop_mtc_daemon()
          outputs.start_mtc_daemon()
          core.save_settings()
        end
      end
    end

    if s.mtc_error then
      ImGui.TextColored(ctx, C.red, "Error: " .. trunc(s.mtc_error, 60))
    elseif s.mtc_enabled then
      local pl = s.mtc_port ~= "" and s.mtc_port or "Virtual Port"
      ImGui.TextColored(ctx, C.green, "Active — " .. pl)
    else
      ImGui.TextColored(ctx, C.dim,
        "Requires python-rtmidi (auto-installed on enable)")
    end

    -- ── LTC Audio Input ───────────────────────────────────────────────────────
    ImGui.SeparatorText(ctx, 'LTC Audio Input')

    local ltc_changed, ltc_val = ImGui.Checkbox(ctx, 'Use LTC', s.ltc_enabled)
    if ltc_changed then
      s.ltc_enabled = ltc_val
      if not ltc_val then
        ltc.destroy_accessor()
        s.ltc_track = nil
        s.ltc_track_guid = nil
        s.tc_valid  = false
      else
        if s.ltc_track_guid ~= nil then
          s.ltc_track = core.get_track_by_guid(s.ltc_track_guid)
        end
      end
      s.peak_level = 0
      core.save_settings()
    end

    -- Track dropdown
    local tc_count    = reaper.CountTracks(0)
    local track_labels = {}
    local cur_track_idx = 0
    if tc_count > 0 then
      for i = 0, tc_count - 1 do
        local tr = reaper.GetTrack(0, i)
        if tr then
          local _, nm = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
          track_labels[i + 1] = nm ~= "" and string.format("%d: %s", i + 1, nm)
                                          or string.format("Track %d", i + 1)
          if s.ltc_track_guid and core.get_track_guid(tr) == s.ltc_track_guid then
            cur_track_idx = i   -- 0-based for ImGui.Combo
          end
        end
      end
    else
      track_labels[1] = "(no tracks)"
    end
    local track_items = table.concat(track_labels, '\0') .. '\0'
    ImGui.SetNextItemWidth(ctx, 280)
    local tr_changed, new_tr_idx = ImGui.Combo(ctx, 'LTC Track', cur_track_idx, track_items)
    if tr_changed and tc_count > 0 then
      local new_track = reaper.GetTrack(0, new_tr_idx)
      if new_track then
        s.ltc_track_guid = core.get_track_guid(new_track)  -- store GUID instead of index
        ltc.on_track_changed()
        s.ltc_track = new_track
        core.save_settings()
      end
    end

    if s.ltc_enabled then
      local fb_changed, fb_val = ImGui.Checkbox(ctx, 'Fallback to Timeline', s.ltc_fallback)
      if fb_changed then
        s.ltc_fallback = fb_val
        core.save_settings()
      end
    end

    -- ── Timecode ─────────────────────────────────────────────────────────────
    ImGui.SeparatorText(ctx, 'Timecode')

    local fr_items = table.concat(core.FR_NAMES, '\0') .. '\0'
    ImGui.SetNextItemWidth(ctx, 200)
    local fr_changed, fr_idx = ImGui.Combo(ctx, 'Frame Rate', s.framerate_type, fr_items)
    if fr_changed then
      s.framerate_type = fr_idx
      core.save_settings()
    end

    ImGui.SetNextItemWidth(ctx, 200)
    local thr_changed, thr_val = ImGui.SliderDouble(
      ctx, 'Threshold (dB)', s.threshold_db, -48, -6, '%.0f dB')
    if thr_changed then
      s.threshold_db = math.floor(thr_val)
      core.save_settings()
    end

    -- LTC status
    if s.ltc_enabled then
      local peak_db = s.peak_level > 0 and (20 * math.log(s.peak_level, 10)) or -96
      ImGui.TextColored(ctx, C.dim,
        string.format("Peak: %.1f dB   Thr: %.0f dB", peak_db, s.threshold_db))
      if not s.ltc_track then
        ImGui.TextColored(ctx, C.orange,
          "Select a track above — JSFX will be inserted automatically")
      elseif not s.ltc_fx_idx then
        ImGui.TextColored(ctx, C.orange, "Searching for JSFX on track...")
      else
        ImGui.TextColored(ctx, C.dim,
          string.format("JSFX active (FX slot %d)", s.ltc_fx_idx + 1))
      end
    end

    ImGui.Spacing(ctx)
    ImGui.TextColored(ctx, C.dim, "v" .. core.VERSION)
  end

  -- ── Public API ─────────────────────────────────────────────────────────────

  -- Returns false when the window is closed (stops the defer loop).
  function M.draw_ui()
    local visible, open = ImGui.Begin(ctx, 'ReaTC v' .. core.VERSION, true)
    if visible then
      local success, err = pcall(function()
        if s.show_settings then
          draw_settings()
        else
          draw_main()
        end
      end)
      if not success then
        ImGui.TextColored(ctx, 0xFF0000FF, "Error: " .. tostring(err))
      end
    end
    ImGui.End(ctx)
    return open
  end

  return M
end
