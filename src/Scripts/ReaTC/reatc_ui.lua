--- ReaTC — https://github.com/paskateknikko/ReaTC
-- Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
--
--- ReaTC UI module — ReaImGui-based window with main TC display and settings popup.
-- Returns a factory function that takes `(core, outputs)` and returns `{ init, draw_ui }`.
-- `draw_ui()` returns false when the window is closed (signals the defer loop to stop).
-- @module reatc_ui
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
  end

  local function push_style()
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 12, 6)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing,    8, 2)
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

  --- Render a Preferred IP (CIDR) + Interface override + resolved status block.
  -- Mirrors the gma3 "Preferred IP / Interface" pattern. The preferred IP is a
  -- portable CIDR (e.g. "10.0.0.0/8"); the interface override is a machine-specific
  -- escape hatch for multi-NIC hosts with overlapping subnets.
  -- Fields are stacked vertically so the block fits in narrow settings windows.
  -- @param id string unique ImGui id suffix
  -- @param pref_ip string current CIDR ("" = none)
  -- @param pref_iface string current interface override ("" = Auto)
  -- @param on_change function(new_ip, new_iface) called on any change
  local function preferred_ip_block(id, pref_ip, pref_iface, on_change)
    ImGui.SetNextItemWidth(ctx, 180)
    local ip_changed, new_ip = ImGui.InputText(ctx, 'Preferred IP##' .. id, pref_ip)
    if ip_changed then
      if new_ip == "" or core.is_valid_cidr(new_ip) then
        on_change(new_ip, pref_iface)
      end
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        "CIDR range (e.g. 10.0.0.0/8) or a single IP.\n" ..
        "Binds the daemon to the local NIC whose IP\n" ..
        "falls inside this range. Leave empty for Auto.")
    end

    ImGui.SetNextItemWidth(ctx, 180)
    local iface_preview = (pref_iface == "") and "Auto" or pref_iface
    if ImGui.BeginCombo(ctx, 'Interface##' .. id, iface_preview) then
      if ImGui.Selectable(ctx, 'Auto (match by Preferred IP)', pref_iface == "") then
        on_change(pref_ip, "")
      end
      for _, it in ipairs(core.list_interfaces()) do
        local label = string.format("%s  \u{2014} %s", it.iface, it.ip)
        if ImGui.Selectable(ctx, label, it.iface == pref_iface) then
          on_change(pref_ip, it.iface)
        end
      end
      ImGui.EndCombo(ctx)
    end
    ImGui.SameLine(ctx, 0, 6)
    if ImGui.SmallButton(ctx, 'Refresh##ifaces-' .. id) then
      core.list_interfaces(true)
    end

    if pref_ip == "" and pref_iface == "" then
      ImGui.TextColored(ctx, C.dim, "Bound to: Auto (OS default route)")
    else
      local _, label = core.resolve_bind_ip(pref_ip, pref_iface)
      if label then
        ImGui.TextColored(ctx, C.dim, "Bound to: " .. label)
      else
        ImGui.TextColored(ctx, C.orange, "No match \u{2014} using default route")
      end
    end
  end

  -- ── Main view ──────────────────────────────────────────────────────────────

  local function output_toggle(id, enabled, error_state)
    local color = error_state and C.red or enabled and C.green or C.dim
    ImGui.TextColored(ctx, color, "\u{25CF}")
    ImGui.SameLine(ctx, 0, 4)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x00000000)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x3A3D5280)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x33384980)
    local clicked = ImGui.Button(ctx, id)
    ImGui.PopStyleColor(ctx, 3)
    return clicked
  end

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
    local ff_color = (tc_color & 0xFFFFFF00) | 0xAA

    -- Large TC display — scale font to fit window, rounded to avoid atlas rebuilds
    local avail_w = ImGui.GetContentRegionAvail(ctx)
    local tc_size = math.floor(math.max(24, math.min(TC_FONT_SIZE * ui_scale, avail_w / 7.2)))
    ImGui.PushFont(ctx, font_tc, tc_size)
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

    -- Output toggle buttons
    if output_toggle('Art-Net', s.artnet_enabled, s.artnet_error) then
      s.artnet_enabled = not s.artnet_enabled
      if s.artnet_enabled then s.packets_sent = 0 else outputs.stop_artnet_daemon() end
      core.save_settings()
    end
    ImGui.SameLine(ctx, 0, 16)
    if output_toggle('OSC', s.osc_enabled, s.osc_error) then
      s.osc_enabled = not s.osc_enabled
      if s.osc_enabled then s.osc_packets_sent = 0 else outputs.stop_osc_daemon() end
      core.save_settings()
    end

    if ImGui.Button(ctx, 'Settings') then
      ImGui.OpenPopup(ctx, 'Settings##popup')
    end
    ImGui.SameLine(ctx, 0, 8)
    ImGui.TextColored(ctx, C.dim, "v" .. core.VERSION)
  end

  -- ── Settings content (rendered inside popup modal) ──────────────────────────

  local function draw_settings()
    -- Close on ESC
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
      ImGui.CloseCurrentPopup(ctx)
    end

    -- ── Art-Net ──────────────────────────────────────────────────────────────
    ImGui.SeparatorText(ctx, 'Art-Net Output')
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.dim)
    ImGui.TextWrapped(ctx, "Art-Net timecode broadcast (lighting consoles, media servers)")
    ImGui.PopStyleColor(ctx)

    local an_changed, an_val = ImGui.Checkbox(ctx, 'Enable##artnet', s.artnet_enabled)
    if an_changed then
      s.artnet_enabled = an_val
      if an_val then s.packets_sent = 0 else outputs.stop_artnet_daemon() end
      core.save_settings()
    end

    ImGui.SameLine(ctx)
    ImGui.SetNextItemWidth(ctx, 220)
    local ip_changed, new_ip = ImGui.InputText(ctx, 'Destination IP', s.dest_ip)
    if ip_changed then
      if core.is_valid_ipv4_list(new_ip) then
        s.dest_ip = new_ip
        core.save_settings()
        if s.artnet_enabled then
          outputs.stop_artnet_daemon()
        end
      elseif new_ip ~= "" then
        ImGui.TextColored(ctx, C.red, "Invalid: use aaa.bbb.ccc.ddd, comma-separated for multi-unicast")
      end
    end
    if ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx,
        "Single IP (e.g. 2.0.0.1 or 192.168.0.50),\n" ..
        "or a comma-separated list for multi-unicast\n" ..
        "(e.g. 192.168.0.50, 192.168.0.51).")
    end

    preferred_ip_block('artnet', s.artnet_preferred_ip, s.artnet_preferred_iface,
      function(new_ip, new_iface)
        local changed = (new_ip ~= s.artnet_preferred_ip)
                     or (new_iface ~= s.artnet_preferred_iface)
        if changed then
          s.artnet_preferred_ip    = new_ip
          s.artnet_preferred_iface = new_iface
          core.save_settings()
          if s.artnet_enabled then outputs.stop_artnet_daemon() end
        end
      end)

    if s.artnet_error then
      ImGui.TextColored(ctx, C.red, "Error: " .. trunc(s.artnet_error, 60))
    elseif s.artnet_enabled and s.artnet_proc then
      ImGui.TextColored(ctx, C.green,
        string.format("Running \u{2014} %d packets sent", s.packets_sent))
    elseif s.artnet_enabled and not s.tc_valid then
      ImGui.TextColored(ctx, C.orange, "Waiting for valid TC")
    elseif s.python_bin then
      ImGui.TextColored(ctx, C.dim, "Python: " .. trunc(s.python_bin, 50))
    else
      ImGui.TextColored(ctx, C.red, "Python 3 not found!")
    end

    -- ── OSC ──────────────────────────────────────────────────────────────────
    ImGui.SeparatorText(ctx, 'OSC Output')
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.dim)
    ImGui.TextWrapped(ctx, "Open Sound Control output (QLab, MA3, EOS, etc.)")
    ImGui.PopStyleColor(ctx)

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
    local osc_port_str = tostring(s.osc_port)
    local osc_port_changed, new_osc_port_str = ImGui.InputText(ctx, 'Port##osc', osc_port_str,
      ImGui.InputTextFlags_CharsDecimal)
    if osc_port_changed then
      local p = tonumber(new_osc_port_str)
      if p and p >= 1 and p <= 65535 then
        s.osc_port = math.floor(p)
        core.save_settings()
        if s.osc_enabled then outputs.stop_osc_daemon() end
      end
    end

    ImGui.SetNextItemWidth(ctx, 180)
    local osc_addr_changed, new_osc_addr = ImGui.InputText(ctx, 'OSC Address##osc', s.osc_address)
    if osc_addr_changed then
      if new_osc_addr:sub(1, 1) == "/" then
        s.osc_address = new_osc_addr
        core.save_settings()
        if s.osc_enabled then outputs.stop_osc_daemon() end
      elseif new_osc_addr ~= "" then
        ImGui.TextColored(ctx, C.red, "OSC address must start with /")
      end
    end

    preferred_ip_block('osc', s.osc_preferred_ip, s.osc_preferred_iface,
      function(new_ip, new_iface)
        local changed = (new_ip ~= s.osc_preferred_ip)
                     or (new_iface ~= s.osc_preferred_iface)
        if changed then
          s.osc_preferred_ip    = new_ip
          s.osc_preferred_iface = new_iface
          core.save_settings()
          if s.osc_enabled then outputs.stop_osc_daemon() end
        end
      end)

    if s.osc_error then
      ImGui.TextColored(ctx, C.red, "Error: " .. trunc(s.osc_error, 60))
    elseif s.osc_enabled and s.osc_proc then
      ImGui.TextColored(ctx, C.green,
        string.format("Running \u{2014} %d packets to %s:%d  %s",
          s.osc_packets_sent, s.osc_ip, s.osc_port, s.osc_address))
    elseif s.osc_enabled and not s.tc_valid then
      ImGui.TextColored(ctx, C.orange, "Waiting for valid TC")
    elseif s.osc_enabled then
      ImGui.TextColored(ctx, C.dim,
        string.format("Sending to %s:%d  %s", s.osc_ip, s.osc_port, s.osc_address))
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
        if oh <= 39 and om <= 59 and os <= 59 and of < fps_max then
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
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.dim)
    ImGui.TextWrapped(ctx, "Create LTC audio items for all project regions")
    ImGui.PopStyleColor(ctx)

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
    push_style()
    ImGui.SetNextWindowSizeConstraints(ctx, 300, 180, 1e9, 1e9)
    local visible, open = ImGui.Begin(ctx, 'ReaTC v' .. core.VERSION, true)
    -- ReaImGui: End() must only be called when Begin() returned visible=true.
    -- When the window is collapsed, visible=false and Begin did not push a
    -- frame; calling End() then trips "End() too many times".
    if visible then
      local win_w = ImGui.GetWindowWidth(ctx)
      ui_scale = math.max(0.6, math.min(2.0, win_w / 480))
      local font_size = math.floor(DEFAULT_FONT_SIZE * ui_scale)
      ImGui.PushFont(ctx, nil, font_size)
      local success, err = pcall(function()
        draw_main()

        -- Settings popup modal (fixed size, centered)
        ImGui.SetNextWindowSizeConstraints(ctx, 460, 340, 800, 1200)
        local modal_visible, modal_open = ImGui.BeginPopupModal(ctx, 'Settings##popup', true)
        if modal_visible then
          if not modal_open then
            ImGui.CloseCurrentPopup(ctx)
          end
          -- Isolate draw_settings errors so EndPopup is always called,
          -- otherwise the popup frame stays on ReaImGui's stack.
          local ok, settings_err = pcall(draw_settings)
          if not ok then
            ImGui.TextColored(ctx, C.red, "Settings error: " .. tostring(settings_err))
          end
          ImGui.EndPopup(ctx)
        end
      end)
      if not success then
        ImGui.TextColored(ctx, 0xFF0000FF, "Error: " .. tostring(err))
      end
      ImGui.PopFont(ctx)
      ImGui.End(ctx)
    end
    ImGui.PopStyleColor(ctx, 18)
    ImGui.PopStyleVar(ctx, 2)
    return open
  end

  return M
end
