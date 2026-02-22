-- ReaTC UI and input handling

return function(core, outputs, ltc)
  local M = {}
  local s = core.state

  local C = {
    bg       = { 0.11, 0.11, 0.13 },
    section  = { 0.17, 0.17, 0.21 },
    text     = { 0.90, 0.90, 0.90 },
    dim      = { 0.50, 0.50, 0.55 },
    green    = { 0.20, 0.85, 0.35 },
    orange   = { 0.95, 0.65, 0.15 },
    red      = { 0.88, 0.25, 0.25 },
    blue     = { 0.35, 0.65, 0.95 },
    field    = { 0.19, 0.19, 0.24 },
    field_hi = { 0.23, 0.32, 0.52 },
    btn      = { 0.27, 0.27, 0.34 },
    btn_hi   = { 0.37, 0.37, 0.50 },
  }

  local function sc(c, a)
    gfx.r = c[1]; gfx.g = c[2]; gfx.b = c[3]; gfx.a = a or 1.0
  end

  local function fill(x, y, w, h, c)
    sc(c); gfx.rect(x, y, w, h, 1)
  end

  local function stroke(x, y, w, h, c)
    sc(c); gfx.rect(x, y, w, h, 0)
  end

  local function put(x, y, str, c)
    sc(c or C.text); gfx.x = x; gfx.y = y; gfx.drawstr(str)
  end

  -- Mouse state (updated each frame)
  local ui = {
    mx = 0, my = 0,
    ldown = false, lclick = false,
    ip_focused = false,
    ip_cursor = 0,
    ip_fresh_octet = true,
    slider_dragging = false,
    dropdown_id = nil,
    dropdown_options = {},
    dropdown_x = 0,
    dropdown_y = 0,
    dropdown_w = 0,
    dropdown_selected = nil
  }

  function M.update_mouse()
    ui.mx = gfx.mouse_x; ui.my = gfx.mouse_y
    local d = (gfx.mouse_cap & 1) ~= 0
    ui.lclick = not d and ui.ldown
    ui.ldown  = d
  end

  local function hit(x, y, w, h)
    return ui.lclick and ui.mx >= x and ui.mx < x + w and ui.my >= y and ui.my < y + h
  end
  local function hover(x, y, w, h)
    return ui.mx >= x and ui.mx < x + w and ui.my >= y and ui.my < y + h
  end

  local function checkbox(x, y, label, checked)
    local bx, by, bw, bh = x, y + 1, 14, 14
    fill(bx, by, bw, bh, hover(bx, by, bw, bh + 4) and C.btn_hi or C.btn)
    stroke(bx, by, bw, bh, C.dim)
    if checked then sc(C.green); gfx.x = bx + 2; gfx.y = by; gfx.drawstr("x") end
    sc(C.text); gfx.x = bx + bw + 5; gfx.y = y; gfx.drawstr(label)
    return hit(bx, by, bw + 5 + gfx.measurestr(label), bh + 4)
  end

  local function button(x, y, w, h, label, col)
    fill(x, y, w, h, col or (hover(x, y, w, h) and C.btn_hi or C.btn))
    stroke(x, y, w, h, C.dim)
    local tw = gfx.measurestr(label)
    sc(C.text); gfx.x = x + (w - tw) / 2; gfx.y = y + (h - 14) / 2
    gfx.drawstr(label)
    return hit(x, y, w, h)
  end

  local function textfield(x, y, w, h, value, focused)
    fill(x, y, w, h, focused and C.field_hi or C.field)
    stroke(x, y, w, h, focused and C.blue or C.dim)
    sc(C.text); gfx.x = x + 4; gfx.y = y + (h - 14) / 2
    local blink = math.floor(reaper.time_precise() * 2) % 2 == 0
    gfx.drawstr(focused and blink and (value .. "|") or value)
    return hit(x, y, w, h)
  end

  local function ip_field(x, y, w, h, value, focused)
    fill(x, y, w, h, focused and C.field_hi or C.field)
    stroke(x, y, w, h, focused and C.blue or C.dim)

    local octets = {}
    for octet in value:gmatch("([^%.]+)") do
      octets[#octets + 1] = octet
    end
    while #octets < 4 do octets[#octets + 1] = "0" end

    sc(C.text)
    gfx.x = x + 4
    gfx.y = y + (h - 14) / 2

    local octet_positions = {}

    for i = 1, 4 do
      local octet_text = octets[i]
      local octet_x = gfx.x
      local tw = gfx.measurestr(octet_text)
      octet_positions[i] = {x = octet_x, w = tw}

      if focused and ui.ip_cursor == i - 1 then
        fill(octet_x - 1, y + 2, tw + 2, h - 4, C.blue)
        sc(C.bg)
        gfx.drawstr(octet_text)
        sc(C.text)
      else
        local is_hover = hover(octet_x - 1, y, tw + 2, h) and not focused
        if is_hover then
          fill(octet_x - 1, y + 2, tw + 2, h - 4, C.btn_hi)
        end
        gfx.drawstr(octet_text)
      end

      if i < 4 then
        gfx.drawstr(".")
      end
    end

    if ui.lclick and hover(x, y, w, h) then
      for i, pos in ipairs(octet_positions) do
        if ui.mx >= pos.x - 1 and ui.mx < pos.x + pos.w + 2 then
          ui.ip_cursor = i - 1
          ui.ip_fresh_octet = true
          return true
        end
      end
    end

    return hit(x, y, w, h)
  end

  local function dropdown(id, x, y, w, h, options, current_idx)
    local is_hover = hover(x, y, w, h)
    local is_open = (ui.dropdown_id == id)

    fill(x, y, w, h, (is_open or is_hover) and C.btn_hi or C.field)
    stroke(x, y, w, h, (is_open or is_hover) and C.blue or C.dim)

    local label = (current_idx and current_idx >= 1 and current_idx <= #options)
                  and options[current_idx] or "(none)"
    sc(C.text); gfx.x = x + 4; gfx.y = y + (h - 14) / 2
    gfx.drawstr(label)

    sc((is_open or is_hover) and C.text or C.dim)
    local arrow = is_open and " ▲" or " ▼"
    local aw = gfx.measurestr(arrow)
    gfx.x = x + w - aw - 2; gfx.y = y + (h - 14) / 2
    gfx.drawstr(arrow)

    if hit(x, y, w, h) then
      if is_open then
        ui.dropdown_id = nil
      else
        ui.dropdown_id = id
        ui.dropdown_x = x
        ui.dropdown_y = y + h
        ui.dropdown_w = w
        ui.dropdown_options = options
      end
    end

    return nil
  end

  local function draw_dropdown_list()
    if not ui.dropdown_id then return end

    local opts = ui.dropdown_options
    if #opts == 0 then return end

    local x, y, w = ui.dropdown_x, ui.dropdown_y, ui.dropdown_w
    local item_h = 20
    local max_items = 10
    local visible_items = math.min(#opts, max_items)
    local list_h = visible_items * item_h

    local button_h = 20
    if ui.lclick and not hover(x, y - button_h, w, button_h) and not hover(x, y, w, list_h) then
      ui.dropdown_id = nil
      ui.dropdown_selected = nil
      return
    end

    fill(x, y, w, list_h, C.bg)
    stroke(x, y, w, list_h, C.blue)

    for i = 1, visible_items do
      local iy = y + (i - 1) * item_h
      local item_hover = hover(x, iy, w, item_h)

      if item_hover then
        fill(x, iy, w, item_h, C.btn_hi)
      end

      sc(C.text)
      gfx.x = x + 4
      gfx.y = iy + (item_h - 14) / 2
      gfx.drawstr(opts[i])

      if item_hover and ui.lclick then
        ui.dropdown_id = nil
        ui.dropdown_selected = i
        return i
      end
    end

    return nil
  end

  local function slider(x, y, w, h, value, min_val, max_val, label)
    local is_hover = hover(x, y, w, h)

    if is_hover and ui.ldown and not ui.slider_dragging then
      ui.slider_dragging = true
    end
    if not ui.ldown then
      ui.slider_dragging = false
    end

    fill(x, y, w, h, (is_hover or ui.slider_dragging) and C.field_hi or C.field)
    stroke(x, y, w, h, (is_hover or ui.slider_dragging) and C.blue or C.dim)

    local range = max_val - min_val
    local norm = (value - min_val) / range
    local track_x = x + 4
    local track_w = w - 8
    local handle_x = track_x + norm * track_w

    fill(track_x, y + h / 2 - 1, track_w, 2, C.dim)
    fill(track_x, y + h / 2 - 1, (handle_x - track_x), 2, C.blue)

    fill(handle_x - 3, y + 3, 6, h - 6, (is_hover or ui.slider_dragging) and C.blue or C.btn_hi)
    stroke(handle_x - 3, y + 3, 6, h - 6, C.text)

    if label then
      sc(C.text)
      local lw = gfx.measurestr(label)
      gfx.x = track_x + (track_w - lw) / 2
      gfx.y = y + (h - 14) / 2
      gfx.drawstr(label)
    end

    local new_value = value
    if ui.slider_dragging then
      local mouse_norm = math.max(0, math.min(1, (ui.mx - track_x) / track_w))
      new_value = min_val + mouse_norm * range
    end

    return new_value, ui.slider_dragging
  end

  local function sec_hdr(x, y, w, label)
    fill(x, y, w, 20, C.section)
    sc(C.dim); gfx.x = x + 6; gfx.y = y + 3; gfx.drawstr(label)
  end

  local function trunc(s, n)
    if #s <= n then return s end
    return s:sub(1, n - 3) .. "..."
  end

  local function draw_main_view()
    fill(0, 0, gfx.w, gfx.h, C.bg)

    local h, m, sec, f, source = core.get_active_tc()
    local tc_str = string.format("%02d:%02d:%02d:%02d", h, m, sec, f)
    local is_ltc_locked = (source == "LTC")

    local target_width = gfx.w * 0.85
    local font_size = math.floor(gfx.w / 8)
    font_size = math.max(24, math.min(font_size, 200))

    gfx.setfont(1, "Courier New", font_size, string.byte("b"))
    local tw, th = gfx.measurestr(tc_str)

    while tw > target_width and font_size > 24 do
      font_size = font_size - 2
      gfx.setfont(1, "Courier New", font_size, string.byte("b"))
      tw, th = gfx.measurestr(tc_str)
    end

    local any_out = s.artnet_enabled or s.mtc_enabled or s.ltc_out_enabled
    local y = (gfx.h - th - 60) / 2

    if is_ltc_locked then
      sc(C.green)
    else
      sc(any_out and C.green or C.dim)
    end
    gfx.x = (gfx.w - tw) / 2
    gfx.y = y
    gfx.drawstr(tc_str)
    y = y + th + 8

    gfx.setfont(1, "Arial", 13, 0)
    local sl, sc_
    if s.ltc_enabled and s.ltc_track ~= nil then
      if is_ltc_locked then
        sl = "LTC LOCKED   " .. core.FR_NAMES[s.framerate_type + 1]
        sc_ = C.green
      else
        if s.ltc_fallback then
          sl = "SEARCHING (Timeline fallback)   " .. core.FR_NAMES[s.framerate_type + 1]
        else
          sl = "SEARCHING (holding)   " .. core.FR_NAMES[s.framerate_type + 1]
        end
        sc_ = C.orange
      end
    else
      if any_out then
        sl = string.format("Timeline   %s", core.FR_NAMES[s.framerate_type + 1])
        sc_ = C.green
      else
        sl = "Timeline   " .. core.FR_NAMES[s.framerate_type + 1] .. "  (idle)"
        sc_ = C.dim
      end
    end
    local slw = gfx.measurestr(sl)
    put((gfx.w - slw) / 2, y, sl, sc_)

    -- Active output badges
    gfx.setfont(1, "Arial", 11, 0)
    local badge_y = gfx.h - 40
    local badges = {
      { label = "Art-Net", active = s.artnet_enabled },
      { label = "MTC",     active = s.mtc_enabled    },
      { label = "LTC Out", active = s.ltc_out_enabled },
    }
    local dot = "● "
    local gap = 8
    -- Measure total width to centre the row
    local total_w = 0
    for i, b in ipairs(badges) do
      local dot_w = gfx.measurestr(dot)
      local lbl_w = gfx.measurestr(b.label)
      total_w = total_w + dot_w + lbl_w + (i < #badges and gap or 0)
    end
    local bx = (gfx.w - total_w) / 2
    for i, b in ipairs(badges) do
      local dot_w = gfx.measurestr(dot)
      sc(b.active and C.green or C.dim)
      gfx.x = bx; gfx.y = badge_y; gfx.drawstr(dot)
      bx = bx + dot_w
      sc(b.active and C.text or C.dim)
      gfx.x = bx; gfx.y = badge_y; gfx.drawstr(b.label)
      bx = bx + gfx.measurestr(b.label) + gap
    end

    gfx.setfont(1, "Arial", 13, 0)
    if button(gfx.w - 110, gfx.h - 36, 100, 28, "⚙ Settings") then
      s.show_settings = true
    end

    gfx.setfont(1, "Arial", 10, 0)
    local vstr = "v" .. core.VERSION
    put(8, gfx.h - 14, vstr, C.dim)
  end

  local function draw_settings_view()
    fill(0, 0, gfx.w, gfx.h, C.bg)
    local x, y = 8, 8
    local W = gfx.w - 16

    gfx.setfont(1, "Arial", 16, string.byte("b"))
    put(x, y + 2, "Settings", C.text)

    gfx.setfont(1, "Courier New", 18, string.byte("b"))
    local h, m, sec, f, source = core.get_active_tc()
    local tc_str = string.format("%02d:%02d:%02d:%02d", h, m, sec, f)
    local is_ltc_locked = (source == "LTC")
    local tw = gfx.measurestr(tc_str)

    if is_ltc_locked then
      sc(C.green)
    else
      sc((s.artnet_enabled or s.mtc_enabled or s.ltc_out_enabled) and C.green or C.dim)
    end
    gfx.x = (gfx.w - tw) / 2
    gfx.y = y + 2
    gfx.drawstr(tc_str)

    gfx.setfont(1, "Arial", 13, 0)
    if button(gfx.w - 80, y, 70, 24, "Close") then
      s.show_settings = false
    end
    y = y + 32

    sec_hdr(x, y, W, "  Art-Net Output")
    y = y + 24

    gfx.setfont(1, "Arial", 13, 0)
    if checkbox(x, y, "Enable", s.artnet_enabled) then
      s.artnet_enabled = not s.artnet_enabled
      if s.artnet_enabled then s.packets_sent = 0 end
      core.save_settings()
    end

    put(x + 82, y + 2, "IP:", C.dim)
    local ip_x, ip_w = x + 104, W - 104
    if ip_field(ip_x, y, ip_w, 20, s.dest_ip, ui.ip_focused) then
      local was_focused = ui.ip_focused
      ui.ip_focused = true
      if not was_focused then
        ui.ip_fresh_octet = true
      end
    elseif ui.lclick and not hover(ip_x, y, ip_w, 20) then
      ui.ip_focused = false
    end
    y = y + 24

    gfx.setfont(1, "Arial", 11, 0)
    if s.artnet_error then
      put(x + 2, y, "Error: " .. trunc(s.artnet_error, 52), C.red)
    elseif s.python_bin then
      put(x + 2, y, "Python: " .. trunc(s.python_bin, 40), C.dim)
    else
      put(x + 2, y, "Python 3 not found!", C.red)
    end
    y = y + 16

    sec_hdr(x, y, W, "  MTC Output")
    y = y + 24

    gfx.setfont(1, "Arial", 13, 0)
    if checkbox(x, y, "Enable MTC", s.mtc_enabled) then
      if not s.mtc_enabled then
        if core.check_rtmidi() or core.try_install_rtmidi() then
          s.mtc_enabled = true
          s.mtc_error   = nil
          if not s.mtc_ports then s.mtc_ports = core.list_midi_ports() end
          outputs.start_mtc_daemon()
        end
      else
        s.mtc_enabled = false
        outputs.stop_mtc_daemon()
        s.mtc_error = nil
      end
      core.save_settings()
    end

    if s.mtc_enabled then
      if ui.dropdown_id == "mtc_port" and not s.mtc_ports then
        s.mtc_ports = core.list_midi_ports()
      end

      local ports = s.mtc_ports or {}
      local port_labels = {}
      local current_idx = nil

      for i, p in ipairs(ports) do
        port_labels[i] = (p.index == -1) and "Virtual Port" or p.name
        if (s.mtc_port == "" and p.index == -1) or
           (s.mtc_port ~= "" and p.name == s.mtc_port) then
          current_idx = i
        end
      end

      put(x, y + 2, "Port:", C.dim)
      local sel = dropdown("mtc_port", x + 50, y - 1, W - 50, 20, port_labels, current_idx)
      if sel then
        local np = ports[sel]
        s.mtc_port = (np.index == -1) and "" or np.name
        outputs.stop_mtc_daemon(); outputs.start_mtc_daemon()
        core.save_settings()
      end
    end
    y = y + 22

    gfx.setfont(1, "Arial", 11, 0)
    if s.mtc_error then
      put(x + 2, y, "Error: " .. trunc(s.mtc_error, 52), C.red)
    elseif s.mtc_enabled then
      local pl = s.mtc_port ~= "" and s.mtc_port or "Virtual Port"
      put(x + 2, y, "Active — " .. pl, C.green)
    else
      put(x + 2, y, "Requires python-rtmidi (auto-installed on enable)", C.dim)
    end
    y = y + 16

    sec_hdr(x, y, W, "  LTC Audio Output")
    y = y + 24

    gfx.setfont(1, "Arial", 13, 0)
    if checkbox(x, y, "Enable LTC Out", s.ltc_out_enabled) then
      if not s.ltc_out_enabled then
        if core.check_sounddevice() or core.try_install_sounddevice() then
          s.ltc_out_enabled = true
          s.ltc_out_error   = nil
          if not s.ltc_out_devices then
            s.ltc_out_devices = core.list_audio_devices()
          end
          outputs.start_ltc_out_daemon()
        end
      else
        s.ltc_out_enabled = false
        outputs.stop_ltc_out_daemon()
        s.ltc_out_error = nil
      end
      core.save_settings()
    end

    if s.ltc_out_enabled then
      if ui.dropdown_id == "ltc_out_device" and not s.ltc_out_devices then
        s.ltc_out_devices = core.list_audio_devices()
      end

      local devs = s.ltc_out_devices or {}
      local dev_labels = {}
      local current_dev_idx = nil

      for i, d in ipairs(devs) do
        dev_labels[i] = (d.index == -1) and "Default Device" or d.name
        if (s.ltc_out_device == "" and d.index == -1) or
           (s.ltc_out_device ~= "" and d.name == s.ltc_out_device) then
          current_dev_idx = i
        end
      end

      put(x, y + 2, "Device:", C.dim)
      local sel = dropdown("ltc_out_device", x + 60, y - 1, W - 60, 20, dev_labels, current_dev_idx)
      if sel then
        local nd = devs[sel]
        s.ltc_out_device = (nd.index == -1) and "" or nd.name
        outputs.stop_ltc_out_daemon(); outputs.start_ltc_out_daemon()
        core.save_settings()
      end
    end
    y = y + 22

    gfx.setfont(1, "Arial", 11, 0)
    if s.ltc_out_error then
      put(x + 2, y, "Error: " .. trunc(s.ltc_out_error, 52), C.red)
    elseif s.ltc_out_enabled then
      local dl = s.ltc_out_device ~= "" and s.ltc_out_device or "Default Device"
      put(x + 2, y, "Active — " .. dl, C.green)
    else
      put(x + 2, y, "Requires sounddevice + numpy (auto-installed on enable)", C.dim)
    end
    y = y + 16

    sec_hdr(x, y, W, "  LTC Audio Input")
    y = y + 24

    gfx.setfont(1, "Arial", 13, 0)
    if checkbox(x, y, "Use LTC", s.ltc_enabled) then
      s.ltc_enabled = not s.ltc_enabled
      if not s.ltc_enabled then
        ltc.destroy_accessor()
        s.ltc_track = nil
        s.tc_valid  = false
      else
        if s.ltc_track_idx ~= nil then
          s.ltc_track = reaper.GetTrack(0, s.ltc_track_idx)
        end
      end
      s.bit_idx = 0
      s.bit_ones = 0
      s.bit_zeros = 0
      s.sync_count = 0
      s.trans_count = 0
      s.peak_level = 0
      core.save_settings()
    end
    y = y + 24

    local tc_count = reaper.CountTracks(0)
    local track_labels = {}
    local current_track_idx = nil

    if tc_count > 0 then
      for i = 0, tc_count - 1 do
        local tr = reaper.GetTrack(0, i)
        if tr then
          local _, nm = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
          track_labels[i + 1] = nm ~= "" and string.format("%d: %s", i + 1, nm)
                                          or string.format("Track %d", i + 1)
          if s.ltc_track_idx == i then
            current_track_idx = i + 1
          end
        end
      end
    else
      track_labels[1] = "(no tracks)"
    end

    put(x, y + 3, "Track:", C.dim)
    local sel = dropdown("ltc_track", x + 50, y, W - 50, 20, track_labels, current_track_idx)
    if sel and tc_count > 0 then
      s.ltc_track_idx = sel - 1
      ltc.destroy_accessor(); s.accessor = nil; s.tc_valid = false
      s.ltc_track = reaper.GetTrack(0, s.ltc_track_idx)
      s.bit_idx = 0
      s.bit_ones = 0
      s.bit_zeros = 0
      s.sync_count = 0
      s.trans_count = 0
      s.peak_level = 0
      core.save_settings()
    end
    y = y + 24

    if s.ltc_enabled then
      if checkbox(x, y, "Fallback to Timeline", s.ltc_fallback) then
        s.ltc_fallback = not s.ltc_fallback
        core.save_settings()
      end
      y = y + 24
    end

    put(x, y + 3, "Rate:", C.dim)
    local sel = dropdown("framerate", x + 40, y, 150, 20, core.FR_NAMES, s.framerate_type + 1)
    if sel then
      s.framerate_type = sel - 1
      s.sig_state = 0; s.bpm_state = 0; s.samples_since_trans = 0
      core.save_settings()
    end
    y = y + 26

    put(x, y + 3, "Threshold:", C.dim)
    local thr_label = string.format("%.0f dB", s.threshold_db)
    local new_thresh, changed = slider(x + 76, y, W - 76, 20, s.threshold_db, -48, -6, thr_label)
    if changed then
      s.threshold_db = math.floor(new_thresh)
      s.sig_state = 0
      s.bpm_state = 0
      s.samples_since_trans = 0
      s.bit_idx = 0
      s.bit_ones = 0
      s.bit_zeros = 0
      s.sync_count = 0
      core.save_settings()
    end
    y = y + 26

    gfx.setfont(1, "Arial", 11, 0)
    if s.ltc_enabled then
      local fps_i = core.FPS_INT[s.framerate_type + 1]
      local spb   = core.DECODER_SRATE / (fps_i * 80)
      put(x, y, string.format("Bits: %d (1s:%d 0s:%d)   Syncs: %d",
        s.bit_idx, s.bit_ones, s.bit_zeros, s.sync_count), C.dim)
      y = y + 14
      local peak_db = s.peak_level > 0 and (20 * math.log(s.peak_level, 10)) or -96
      put(x, y, string.format("Peak: %.1f dB   Transitions: %d   Gap: %.1f",
        peak_db, s.trans_count, s.last_gap), C.dim)
      y = y + 14
      put(x, y, string.format("Expected - Short:%.1f  Full:%.1f  Thr:%.3f",
        spb * 0.75, spb, 10 ^ (s.threshold_db / 20)), C.dim)
      y = y + 14
      local check_lsb, check_msb = 0, 0
      if s.bit_idx >= 16 then
        for i = 0, 15 do
          local idx = (((s.bit_idx - 16 + i) & 511) + 1)
          check_lsb = check_lsb | (s.bit_buf[idx] << i)
          check_msb = check_msb | (s.bit_buf[idx] << (15 - i))
        end
      end
      put(x, y, string.format("LSB: 0x%04X   MSB: 0x%04X   (want 3FFD/BFFC)",
        check_lsb, check_msb), C.dim)
      y = y + 14
      if not s.ltc_track then
        put(x, y, "Select a track above to decode LTC", C.orange)
        y = y + 14
      elseif s.bit_idx > 100 and s.sync_count == 0 then
        if s.bit_ones == 0 then
          put(x, y, "All bits are 0 — signal too weak or wrong polarity", C.orange)
        else
          put(x, y, "Bits received but no sync — adjust threshold or check rate", C.orange)
        end
        y = y + 14
      end
    end

    gfx.setfont(1, "Arial", 10, 0)
    local vstr = "v" .. core.VERSION
    local vw   = gfx.measurestr(vstr)
    put(gfx.w - vw - 4, gfx.h - 14, vstr, C.dim)
  end

  function M.draw_ui()
    if s.show_settings then
      draw_settings_view()
    else
      draw_main_view()
    end

    draw_dropdown_list()
  end

  function M.handle_key(c)
    if not ui.ip_focused or c == 0 then return end

    local shift_held = (gfx.mouse_cap & 8) ~= 0

    local octets = {}
    for octet in s.dest_ip:gmatch("([^%.]+)") do
      octets[#octets + 1] = tonumber(octet) or 0
    end
    while #octets < 4 do octets[#octets + 1] = 0 end

    local idx = ui.ip_cursor + 1

    if c == 1818584692 then
      ui.ip_cursor = math.max(0, ui.ip_cursor - 1)
      ui.ip_fresh_octet = true
    elseif c == 1919379572 then
      ui.ip_cursor = math.min(3, ui.ip_cursor + 1)
      ui.ip_fresh_octet = true
    elseif c == 30064 then
      octets[idx] = math.min(255, octets[idx] + 1)
      s.dest_ip = string.format("%d.%d.%d.%d", octets[1], octets[2], octets[3], octets[4])
      ui.ip_fresh_octet = true
      core.save_settings()
    elseif c == 1685026670 then
      octets[idx] = math.max(0, octets[idx] - 1)
      s.dest_ip = string.format("%d.%d.%d.%d", octets[1], octets[2], octets[3], octets[4])
      ui.ip_fresh_octet = true
      core.save_settings()
    elseif c == 8 or c == 127 then
      local s_oct = tostring(octets[idx])
      if #s_oct > 1 then
        s_oct = s_oct:sub(1, -2)
        octets[idx] = tonumber(s_oct) or 0
        ui.ip_fresh_octet = false
      else
        octets[idx] = 0
        ui.ip_fresh_octet = true
      end
      s.dest_ip = string.format("%d.%d.%d.%d", octets[1], octets[2], octets[3], octets[4])
      core.save_settings()
    elseif c == 13 then
      ui.ip_focused = false
      core.save_settings()
    elseif c == 27 then
      ui.ip_focused = false
    elseif c == 9 then
      if shift_held then
        if ui.ip_cursor > 0 then
          ui.ip_cursor = ui.ip_cursor - 1
          ui.ip_fresh_octet = true
        end
      else
        if ui.ip_cursor < 3 then
          ui.ip_cursor = ui.ip_cursor + 1
          ui.ip_fresh_octet = true
        end
      end
    elseif c == 46 then
      if ui.ip_cursor < 3 then
        ui.ip_cursor = ui.ip_cursor + 1
        ui.ip_fresh_octet = true
      end
    elseif c >= 48 and c <= 57 then
      local digit = c - 48
      local new_val

      if ui.ip_fresh_octet then
        new_val = digit
        ui.ip_fresh_octet = false
      else
        local s_oct = tostring(octets[idx])
        s_oct = s_oct .. tostring(digit)
        new_val = tonumber(s_oct) or 0
      end

      if new_val <= 255 then
        octets[idx] = new_val
        s.dest_ip = string.format("%d.%d.%d.%d", octets[1], octets[2], octets[3], octets[4])
        core.save_settings()
      end
    end
  end

  return M
end
