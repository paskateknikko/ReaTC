-- ReaTC — https://github.com/paskateknikko/ReaTC
-- Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
--
-- ReaTC UI — ReaImGui implementation
-- @noindex
-- @version {{VERSION}}

return function(core, outputs)
  local M = {}
  local s = core.state

  -- Load ReaImGui
  package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
  local ImGui = require 'imgui' '0.10'

  local ctx, font_tc
  local ui_scale = 1.0
  local DEFAULT_FONT_SIZE = 14
  local TC_FONT_SIZE = 72

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
    font_tc = ImGui.CreateFont('Courier New', ImGui.FontFlags_Bold)
    ImGui.Attach(ctx, font_tc)

    -- Dark style matching JSFX palette
    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg,        0x0F0F17FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg,         0x1A1C25FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive,   0x1A1C25FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg,         0x1E2029FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg,         0x262833FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered,  0x2D3040FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive,   0x333849FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_Border,          0x333849FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button,          0x2D3040FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered,   0x3A3D52FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive,    0x333849FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_CheckMark,       0x33D95AFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab,      0x3A3D52FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive,0x5AA4F2FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_Header,          0x2D3040FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered,   0x3A3D52FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive,    0x333849FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text,            0xE5E5E5FF)
  end

  local function trunc(str, n)
    if #str <= n then return str end
    return str:sub(1, n - 3) .. "..."
  end

  -- ── Main view ──────────────────────────────────────────────────────────────

  local function draw_main()
    local h, m, sec, f, source = core.get_active_tc()

    -- TC color based on active source
    local tc_color
    if source == "LTC" or source == "MTC" then
      tc_color = C.green
    elseif source == "Timeline" then
      tc_color = (s.artnet_enabled or s.osc_enabled) and C.green or C.dim
    else
      tc_color = C.dim
    end
    -- Dimmed variant for frames field
    local ff_color = (tc_color & 0xFFFFFF00) | 0xAA

    -- Large TC display
    ImGui.PushFont(ctx, font_tc, TC_FONT_SIZE * ui_scale)
    local hms_str = string.format("%02d:%02d:%02d", h, m, sec)
    local ff_str  = string.format(":%02d", f)
    ImGui.TextColored(ctx, tc_color, hms_str)
    ImGui.SameLine(ctx, 0, 0)
    ImGui.TextColored(ctx, ff_color, ff_str)
    ImGui.PopFont(ctx)

    -- Status line
    local sl, sl_color
    if source == "LTC" then
      sl       = "LTC Locked   " .. core.FR_NAMES[s.framerate_type + 1]
      sl_color = C.green
    elseif source == "MTC" then
      sl       = "MTC Locked   " .. core.FR_NAMES[s.framerate_type + 1]
      sl_color = C.blue
    elseif source == "Timeline" then
      sl       = "Timeline   " .. core.FR_NAMES[s.framerate_type + 1]
      sl_color = (s.artnet_enabled or s.osc_enabled) and C.green or C.dim
    else
      sl       = "No active source   " .. core.FR_NAMES[s.framerate_type + 1]
      sl_color = C.dim
    end
    ImGui.TextColored(ctx, sl_color, sl)

    -- Offset indicator
    if (s.tc_offset_h + s.tc_offset_m + s.tc_offset_s + s.tc_offset_f) > 0 then
      local sign = s.tc_offset_negative and "-" or "+"
      ImGui.TextColored(ctx, C.orange,
        string.format("OFFSET %s%02d:%02d:%02d:%02d",
          sign, s.tc_offset_h, s.tc_offset_m, s.tc_offset_s, s.tc_offset_f))
    end

    -- JSFX detection warning
    if not s.jsfx_detected then
      ImGui.TextColored(ctx, C.orange,
        "JSFX not detected \u{2014} add ReaTC Timecode Converter to any track")
    end

    -- Output status indicators
    ImGui.Spacing(ctx)
    local an_color  = s.artnet_error and C.red or s.artnet_enabled and C.green or C.dim
    local osc_color = s.osc_error    and C.red or s.osc_enabled    and C.green or C.dim
    ImGui.TextColored(ctx, an_color, "\u{25CF}")
    ImGui.SameLine(ctx, 0, 4)
    local an_label = "Art-Net"
    if s.artnet_enabled and s.packets_sent > 0 then
      an_label = string.format("Art-Net (%d)", s.packets_sent)
    end
    ImGui.TextColored(ctx, C.text, an_label)
    ImGui.SameLine(ctx, 0, 16)
    ImGui.TextColored(ctx, osc_color, "\u{25CF}")
    ImGui.SameLine(ctx, 0, 4)
    local osc_label = "OSC"
    if s.osc_enabled and s.osc_packets_sent > 0 then
      osc_label = string.format("OSC (%d)", s.osc_packets_sent)
    end
    ImGui.TextColored(ctx, C.text, osc_label)

    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, 'Settings') then
      ImGui.OpenPopup(ctx, 'Settings##popup')
    end
    ImGui.Spacing(ctx)
    ImGui.TextColored(ctx, C.dim, "v" .. core.VERSION)
  end

  -- ── Settings content (rendered inside popup modal) ──────────────────────────

  local function draw_settings()
    -- ── Art-Net ──────────────────────────────────────────────────────────────
    ImGui.SeparatorText(ctx, 'Art-Net Output')

    local an_changed, an_val = ImGui.Checkbox(ctx, 'Enable##artnet', s.artnet_enabled)
    if an_changed then
      s.artnet_enabled = an_val
      if an_val then s.packets_sent = 0 else outputs.stop_artnet_daemon() end
      core.save_settings()
    end

    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 180)
    local ip_changed, new_ip = ImGui.InputText(ctx, 'Destination IP', s.dest_ip)
    if ip_changed then
      if core.is_valid_ipv4(new_ip) then
        s.dest_ip = new_ip
        core.save_settings()
        if s.artnet_enabled then
          outputs.stop_artnet_daemon()
        end
      elseif new_ip ~= "" then
        ImGui.TextColored(ctx, C.red, "Invalid IP: must be aaa.bbb.ccc.ddd (0-255 each)")
      end
    end

    if s.artnet_error then
      ImGui.TextColored(ctx, C.red, "Error: " .. trunc(s.artnet_error, 60))
    elseif s.artnet_enabled and s.artnet_proc then
      ImGui.TextColored(ctx, C.green,
        string.format("Running — %d packets sent", s.packets_sent))
    elseif s.artnet_enabled and not s.tc_valid then
      ImGui.TextColored(ctx, C.orange, "Waiting for valid TC")
    elseif s.python_bin then
      ImGui.TextColored(ctx, C.dim, "Python: " .. trunc(s.python_bin, 50))
    else
      ImGui.TextColored(ctx, C.red, "Python 3 not found!")
    end

    -- ── OSC ──────────────────────────────────────────────────────────────────
    ImGui.SeparatorText(ctx, 'OSC Output')

    local osc_changed, osc_val = ImGui.Checkbox(ctx, 'Enable##osc', s.osc_enabled)
    if osc_changed then
      s.osc_enabled = osc_val
      if osc_val then s.osc_packets_sent = 0 else outputs.stop_osc_daemon() end
      core.save_settings()
    end

    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 180)
    local osc_ip_changed, new_osc_ip = ImGui.InputText(ctx, 'Destination IP##osc', s.osc_ip)
    if osc_ip_changed then
      if core.is_valid_ipv4(new_osc_ip) then
        s.osc_ip = new_osc_ip
        core.save_settings()
        if s.osc_enabled then outputs.stop_osc_daemon() end
      elseif new_osc_ip ~= "" then
        ImGui.TextColored(ctx, C.red, "Invalid IP: must be aaa.bbb.ccc.ddd (0-255 each)")
      end
    end

    ImGui.SetNextItemWidth(ctx, 80)
    local osc_port_changed, new_osc_port = ImGui.InputInt(ctx, 'Port##osc', s.osc_port)
    if osc_port_changed then
      s.osc_port = math.max(1, math.min(65535, new_osc_port))
      core.save_settings()
      if s.osc_enabled then outputs.stop_osc_daemon() end
    end

    ImGui.SetNextItemWidth(ctx, 180)
    local osc_addr_changed, new_osc_addr = ImGui.InputText(ctx, 'OSC Address##osc', s.osc_address)
    if osc_addr_changed then
      s.osc_address = new_osc_addr
      core.save_settings()
      if s.osc_enabled then outputs.stop_osc_daemon() end
    end

    if s.osc_error then
      ImGui.TextColored(ctx, C.red, "Error: " .. trunc(s.osc_error, 60))
    elseif s.osc_enabled and s.osc_proc then
      ImGui.TextColored(ctx, C.green,
        string.format("Running — %d packets to %s:%d  %s",
          s.osc_packets_sent, s.osc_ip, s.osc_port, s.osc_address))
    elseif s.osc_enabled and not s.tc_valid then
      ImGui.TextColored(ctx, C.orange, "Waiting for valid TC")
    elseif s.osc_enabled then
      ImGui.TextColored(ctx, C.dim,
        string.format("Sending to %s:%d  %s", s.osc_ip, s.osc_port, s.osc_address))
    else
      ImGui.TextColored(ctx, C.dim, "Open Sound Control output (QLab, MA3, EOS, etc.)")
    end

    -- ── Timecode ─────────────────────────────────────────────────────────────
    ImGui.SeparatorText(ctx, 'Timecode')

    ImGui.TextColored(ctx, C.dim,
      "TC sources, outputs, and framerate are configured in the")
    ImGui.TextColored(ctx, C.blue, "ReaTC Timecode Converter")
    ImGui.SameLine(ctx, 0, 4)
    ImGui.TextColored(ctx, C.dim, "JSFX plugin.")
    ImGui.TextColored(ctx, C.dim,
      "Add it to any track from the FX browser.")

    -- ── TC Offset ──────────────────────────────────────────────────────────
    ImGui.SeparatorText(ctx, 'TC Offset')

    local fps_max = core.FPS_INT[s.framerate_type + 1] or 30

    -- Format current offset as editable string
    local sign = s.tc_offset_negative and "-" or "+"
    local offset_str = string.format("%s%02d:%02d:%02d:%02d",
      sign, s.tc_offset_h, s.tc_offset_m, s.tc_offset_s, s.tc_offset_f)

    ImGui.SetNextItemWidth(ctx, 160)
    local off_changed, new_off = ImGui.InputText(ctx, 'Offset##off', offset_str)
    if off_changed then
      local sg, oh, om, os, of = new_off:match("^([+-])(%d%d):(%d%d):(%d%d):(%d%d)$")
      if sg then
        oh, om, os, of = tonumber(oh), tonumber(om), tonumber(os), tonumber(of)
        if oh <= 23 and om <= 59 and os <= 59 and of < fps_max then
          s.tc_offset_negative = (sg == "-")
          s.tc_offset_h = oh
          s.tc_offset_m = om
          s.tc_offset_s = os
          s.tc_offset_f = of
          core.save_settings()
        end
      end
    end

    ImGui.SameLine(ctx, 0, 12)
    if ImGui.Button(ctx, 'Reset##offset') then
      s.tc_offset_h = 0; s.tc_offset_m = 0
      s.tc_offset_s = 0; s.tc_offset_f = 0
      s.tc_offset_negative = false
      core.save_settings()
    end

    -- ── Tools ────────────────────────────────────────────────────────────────
    ImGui.SeparatorText(ctx, 'Tools')

    if ImGui.Button(ctx, 'Bake LTC from Regions...') then
      ImGui.CloseCurrentPopup(ctx)
      dofile(core.script_path .. "reatc_regions_to_ltc.lua")
    end
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, C.dim, "Create LTC audio items for all project regions")

    ImGui.Spacing(ctx)
    ImGui.TextColored(ctx, C.dim, "v" .. core.VERSION)
    ImGui.Spacing(ctx)
    if ImGui.Button(ctx, 'Close##settings') then
      ImGui.CloseCurrentPopup(ctx)
    end
  end

  -- ── Public API ─────────────────────────────────────────────────────────────

  -- Returns false when the window is closed (stops the defer loop).
  function M.draw_ui()
    ImGui.SetNextWindowSizeConstraints(ctx, 360, 120, 1e9, 1e9)
    local visible, open = ImGui.Begin(ctx, 'ReaTC v' .. core.VERSION, true)
    if visible then
      local win_w = ImGui.GetWindowWidth(ctx)
      ui_scale = math.max(0.6, math.min(2.0, win_w / 480))
      ImGui.PushFont(ctx, nil, DEFAULT_FONT_SIZE * ui_scale)
      local success, err = pcall(function()
        draw_main()

        -- Settings popup modal (floats over main view)
        local modal_visible, modal_open = ImGui.BeginPopupModal(ctx, 'Settings##popup', true)
        if modal_visible then
          if not modal_open then
            ImGui.CloseCurrentPopup(ctx)
          end
          draw_settings()
          ImGui.EndPopup(ctx)
        end
      end)
      if not success then
        ImGui.TextColored(ctx, 0xFF0000FF, "Error: " .. tostring(err))
      end
      ImGui.PopFont(ctx)
    end
    ImGui.End(ctx)
    return open
  end

  return M
end
