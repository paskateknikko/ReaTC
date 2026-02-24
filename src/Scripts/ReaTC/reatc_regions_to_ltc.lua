-- ReaTC — https://github.com/paskateknikko/ReaTC
-- Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
--
-- Standalone script: Regions to LTC — generate LTC audio items from project regions
-- @noindex
-- @version {{VERSION}}

if not reaper.ImGui_GetBuiltinPath then
  reaper.MB(
    'ReaImGui not installed.\n\nInstall it from ReaPack (ReaTeam Extensions → ReaImGui).',
    'ReaTC — Regions to LTC', 0)
  return
end

local script_path
do
  local info = debug.getinfo(1, "S")
  script_path = info.source:match("@(.+[\\/])") or ""
end

local core = dofile(script_path .. "reatc_core.lua")

-- Load ReaImGui
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua'
local ImGui = require 'imgui' '0.9'

-- ── Constants ──────────────────────────────────────────────────────────────

local FPS_NAMES  = core.FR_NAMES
local FPS_COUNT  = #FPS_NAMES

local py_ltcgen = script_path .. "reatc_ltcgen.py"

-- ── State ──────────────────────────────────────────────────────────────────

local state = {
  regions       = {},
  track_name    = "LTC [rendered]",
  file_template = "{name}_{fps}",
  level_dbfs    = -6,
  bulk_fps_type = 1,  -- default 25fps (EBU), 1-based for combo
}

-- ── Colors ─────────────────────────────────────────────────────────────────

local C = {
  text   = 0xE5E5E5FF,
  green  = 0x33D95AFF,
  orange = 0xF2A626FF,
  red    = 0xE14040FF,
  dim    = 0x80808CFF,
  blue   = 0x5AA4F2FF,
}

-- ── ImGui context ──────────────────────────────────────────────────────────

local ctx = ImGui.CreateContext('ReaTC — Regions to LTC')

-- Push dark style
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

-- ── Helpers ────────────────────────────────────────────────────────────────

local function collect_regions()
  local regions = {}
  local total = reaper.CountProjectMarkers(0)
  for i = 0, total - 1 do
    local _, isrgn, pos, rgnend, name, rgn_idx = reaper.EnumProjectMarkers(0, i)
    if isrgn and rgnend > pos then
      regions[#regions + 1] = {
        pos      = pos,
        endpos   = rgnend,
        name     = name or "",
        index    = rgn_idx,
      }
    end
  end
  return regions
end

local function build_region_table(raw)
  local entries = {}
  for _, r in ipairs(raw) do
    entries[#entries + 1] = {
      pos      = r.pos,
      endpos   = r.endpos,
      name     = r.name,
      index    = r.index,
      selected = true,
      tc_str   = "00:00:00:00",
      tc_h     = 0,
      tc_m     = 0,
      tc_s     = 0,
      tc_f     = 0,
      fps_type = state.bulk_fps_type,  -- 1-based
    }
  end
  return entries
end

local function safe_filename(str, max_len)
  return str:gsub('[^%w%-_ ]', '_'):sub(1, max_len or 40)
end

local function format_filename(template, rgn)
  local fps_name = FPS_NAMES[rgn.fps_type] or "25fps"
  local tc_str = string.format("%02d%02d%02d%02d", rgn.tc_h, rgn.tc_m, rgn.tc_s, rgn.tc_f)
  local name = rgn.name ~= "" and rgn.name or ("region" .. rgn.index)
  local result = template
  result = result:gsub("{name}",  safe_filename(name))
  result = result:gsub("{tc}",    tc_str)
  result = result:gsub("{fps}",   fps_name:gsub("[^%w]", ""))
  result = result:gsub("{index}", tostring(rgn.index))
  if result == "" then result = "ltc_" .. rgn.index end
  return result
end

local function dbfs_to_amplitude(dbfs)
  return math.floor(32767 * 10 ^ (dbfs / 20))
end

local function get_or_create_track(name)
  for i = 0, reaper.CountTracks(0) - 1 do
    local tr = reaper.GetTrack(0, i)
    local _, nm = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if nm == name then return tr end
  end
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, false)
  local tr = reaper.GetTrack(0, idx)
  reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true)
  return tr
end

local function count_selected()
  local n = 0
  for _, r in ipairs(state.regions) do
    if r.selected then n = n + 1 end
  end
  return n
end

local function parse_tc_string(str, fps_max)
  local h, m, s, f = str:match("^(%d%d):(%d%d):(%d%d):(%d%d)$")
  if not h then return nil end
  h, m, s, f = tonumber(h), tonumber(m), tonumber(s), tonumber(f)
  if h > 23 or m > 59 or s > 59 or f >= fps_max then return nil end
  return h, m, s, f
end

local function clamp_frame(rgn)
  local fps_max = core.FPS_INT[rgn.fps_type] or 30
  if rgn.tc_f >= fps_max then
    rgn.tc_f = fps_max - 1
    rgn.tc_str = string.format("%02d:%02d:%02d:%02d", rgn.tc_h, rgn.tc_m, rgn.tc_s, rgn.tc_f)
  end
end

-- ── Initial region load ────────────────────────────────────────────────────

state.regions = build_region_table(collect_regions())

-- Detect Python once
local python_bin = core.find_python()

-- ── Generation ─────────────────────────────────────────────────────────────

local function generate_selected()
  if not python_bin then
    reaper.MB(
      "Python 3 is required to generate LTC audio.\n\n" ..
      "Install Python 3 and restart REAPER.",
      "ReaTC — Bake LTC", 0)
    return
  end

  local proj_path = reaper.GetProjectPath("")
  if proj_path == "" then
    reaper.MB(
      "Please save the project before baking LTC.\n\n" ..
      "The WAV files will be placed in a 'ReaTC_LTC' sub-folder next to the project.",
      "ReaTC — Bake LTC", 0)
    return
  end

  local selected = {}
  for _, r in ipairs(state.regions) do
    if r.selected then selected[#selected + 1] = r end
  end
  if #selected == 0 then return end

  local sep     = core.is_win and "\\" or "/"
  local ltc_dir = proj_path .. sep .. "ReaTC_LTC"

  if core.is_win then
    os.execute('if not exist "' .. ltc_dir .. '" mkdir "' .. ltc_dir .. '"')
  else
    os.execute('mkdir -p "' .. ltc_dir .. '"')
  end

  local sample_rate = math.floor(reaper.GetSetProjectInfo(0, "SAMPLERATE", 0, false))
  if sample_rate <= 0 then sample_rate = 48000 end

  local amplitude = dbfs_to_amplitude(state.level_dbfs)
  amplitude = math.max(1, math.min(32767, amplitude))

  local q = core.is_win and ('"' .. python_bin .. '"') or python_bin

  local track    = get_or_create_track(state.track_name)
  local ok_count = 0
  local err_list = {}

  -- Track used filenames for deduplication
  local used_names = {}

  reaper.Undo_BeginBlock()

  for _, rgn in ipairs(selected) do
    local duration = rgn.endpos - rgn.pos
    local fr_type  = rgn.fps_type - 1  -- convert to 0-based for Python
    local fps_val  = core.FPS_VAL[rgn.fps_type]

    local n_frames = math.ceil(duration * fps_val) + 1

    local base_name = format_filename(state.file_template, rgn)
    -- Deduplicate
    local fname = base_name
    local suffix = 1
    while used_names[fname] do
      suffix = suffix + 1
      fname = base_name .. "_" .. suffix
    end
    used_names[fname] = true

    local wav_path = ltc_dir .. sep .. safe_filename(fname) .. ".wav"

    local cmd = string.format('%s "%s" %d %d %d %d %d %d %d "%s" %d %s',
      q, py_ltcgen,
      fr_type, rgn.tc_h, rgn.tc_m, rgn.tc_s, rgn.tc_f,
      n_frames, sample_rate,
      wav_path, amplitude,
      core.dev_null)

    os.execute(cmd)

    local src = reaper.PCM_Source_CreateFromFile(wav_path)
    if src then
      local item = reaper.AddMediaItemToTrack(track)
      reaper.SetMediaItemPosition(item, rgn.pos, false)
      reaper.SetMediaItemLength(item, duration, false)
      local take = reaper.AddTakeToMediaItem(item)
      reaper.SetMediaItemTake_Source(take, src)
      local take_name = rgn.name ~= "" and ("LTC " .. rgn.name)
                                        or ("LTC Region " .. rgn.index)
      reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", take_name, true)
      ok_count = ok_count + 1
    else
      err_list[#err_list + 1] = fname
    end
  end

  reaper.Undo_EndBlock("ReaTC: Bake LTC from regions", -1)
  reaper.UpdateArrange()

  if ok_count == #selected then
    reaper.MB(
      string.format(
        "Done! Added %d LTC item(s) to track '%s'.\n\nFiles: %s",
        ok_count, state.track_name, ltc_dir),
      "ReaTC — Bake LTC", 0)
  else
    reaper.MB(
      string.format(
        "%d/%d region(s) succeeded.\n\nFailed: %s\n\n" ..
        "Make sure Python 3 is accessible and the project folder is writable.",
        ok_count, #selected, table.concat(err_list, ", ")),
      "ReaTC — Bake LTC", 0)
  end
end

-- ── UI Drawing ─────────────────────────────────────────────────────────────

local function draw_ui()
  ImGui.SetNextWindowSizeConstraints(ctx, 600, 400, 1e9, 1e9)
  local visible, open = ImGui.Begin(ctx, 'ReaTC \u{2014} Bake LTC', true)
  if not visible then
    ImGui.End(ctx)
    return open
  end

  local win_w = ImGui.GetWindowWidth(ctx)
  local scale = math.max(0.7, math.min(1.5, win_w / 600))
  ImGui.SetWindowFontScale(ctx, scale)

  local n_selected = count_selected()
  local n_regions  = #state.regions

  -- ── Python warning ───────────────────────────────────────────────────
  if not python_bin then
    ImGui.TextColored(ctx, C.orange, "Python 3 not found \u{2014} generation disabled")
    ImGui.Spacing(ctx)
  end

  -- ── Toolbar ──────────────────────────────────────────────────────────
  if ImGui.Button(ctx, 'Select All') then
    for _, r in ipairs(state.regions) do r.selected = true end
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, 'Select None') then
    for _, r in ipairs(state.regions) do r.selected = false end
  end
  ImGui.SameLine(ctx, 0, 16)
  ImGui.TextColored(ctx, C.dim, "Set All:")
  ImGui.SameLine(ctx)
  ImGui.SetNextItemWidth(ctx, 130 * scale)
  local bulk_changed, bulk_new = ImGui.Combo(ctx, '##bulk_fps', state.bulk_fps_type - 1,
    table.concat(FPS_NAMES, '\0') .. '\0')
  if bulk_changed then
    state.bulk_fps_type = bulk_new + 1
    for _, r in ipairs(state.regions) do
      r.fps_type = state.bulk_fps_type
      clamp_frame(r)
    end
  end
  ImGui.SameLine(ctx, 0, 16)
  if ImGui.Button(ctx, 'Refresh') then
    state.regions = build_region_table(collect_regions())
  end

  ImGui.Spacing(ctx)

  -- ── Region table ─────────────────────────────────────────────────────
  if n_regions == 0 then
    ImGui.TextColored(ctx, C.dim, "No regions in project. Create regions on the timeline first.")
  else
    local table_flags = ImGui.TableFlags_Borders
                      | ImGui.TableFlags_RowBg
                      | ImGui.TableFlags_ScrollY
                      | ImGui.TableFlags_SizingStretchProp

    -- Reserve space for bottom controls
    local avail_y = ImGui.GetContentRegionAvail(ctx)
    local table_h = math.max(100, avail_y - 120 * scale)

    if ImGui.BeginTable(ctx, 'regions', 4, table_flags, 0, table_h) then
      ImGui.TableSetupColumn(ctx, ' ',           ImGui.TableColumnFlags_WidthFixed, 30 * scale)
      ImGui.TableSetupColumn(ctx, 'Region Name', ImGui.TableColumnFlags_WidthStretch)
      ImGui.TableSetupColumn(ctx, 'TC Start',    ImGui.TableColumnFlags_WidthFixed, 110 * scale)
      ImGui.TableSetupColumn(ctx, 'Framerate',   ImGui.TableColumnFlags_WidthFixed, 140 * scale)
      ImGui.TableHeadersRow(ctx)

      for i, rgn in ipairs(state.regions) do
        ImGui.TableNextRow(ctx)

        -- Checkbox
        ImGui.TableSetColumnIndex(ctx, 0)
        local sel_changed, sel_new = ImGui.Checkbox(ctx, '##sel' .. i, rgn.selected)
        if sel_changed then rgn.selected = sel_new end

        -- Name
        ImGui.TableSetColumnIndex(ctx, 1)
        local display_name = rgn.name ~= "" and rgn.name or ("Region " .. rgn.index)
        ImGui.TextColored(ctx, C.text, display_name)

        -- TC Start
        ImGui.TableSetColumnIndex(ctx, 2)
        ImGui.SetNextItemWidth(ctx, -1)
        local tc_changed, tc_new = ImGui.InputText(ctx, '##tc' .. i, rgn.tc_str)
        if tc_changed then
          local fps_max = core.FPS_INT[rgn.fps_type] or 30
          local h, m, s, f = parse_tc_string(tc_new, fps_max)
          if h then
            rgn.tc_h = h; rgn.tc_m = m; rgn.tc_s = s; rgn.tc_f = f
            rgn.tc_str = string.format("%02d:%02d:%02d:%02d", h, m, s, f)
          else
            rgn.tc_str = tc_new  -- keep typing state
          end
        end

        -- Framerate
        ImGui.TableSetColumnIndex(ctx, 3)
        ImGui.SetNextItemWidth(ctx, -1)
        local fps_changed, fps_new = ImGui.Combo(ctx, '##fps' .. i, rgn.fps_type - 1,
          table.concat(FPS_NAMES, '\0') .. '\0')
        if fps_changed then
          rgn.fps_type = fps_new + 1
          clamp_frame(rgn)
        end
      end

      ImGui.EndTable(ctx)
    end
  end

  -- ── Output settings ──────────────────────────────────────────────────
  ImGui.Spacing(ctx)

  ImGui.TextColored(ctx, C.dim, "Track:")
  ImGui.SameLine(ctx, 80 * scale)
  ImGui.SetNextItemWidth(ctx, 200 * scale)
  local trk_changed, trk_new = ImGui.InputText(ctx, '##track', state.track_name)
  if trk_changed then state.track_name = trk_new end

  ImGui.TextColored(ctx, C.dim, "Template:")
  ImGui.SameLine(ctx, 80 * scale)
  ImGui.SetNextItemWidth(ctx, 200 * scale)
  local tpl_changed, tpl_new = ImGui.InputText(ctx, '##template', state.file_template)
  if tpl_changed then state.file_template = tpl_new end
  ImGui.SameLine(ctx)
  ImGui.TextColored(ctx, C.dim, "{name} {tc} {fps} {index}")

  ImGui.TextColored(ctx, C.dim, "Level:")
  ImGui.SameLine(ctx, 80 * scale)
  ImGui.SetNextItemWidth(ctx, 200 * scale)
  local lvl_changed, lvl_new = ImGui.SliderInt(ctx, '##level', state.level_dbfs, -48, 0,
    '%d dBFS')
  if lvl_changed then state.level_dbfs = lvl_new end

  -- ── Generate button ──────────────────────────────────────────────────
  ImGui.Spacing(ctx)
  local can_generate = python_bin and n_selected > 0
  if not can_generate then
    ImGui.BeginDisabled(ctx)
  end
  if ImGui.Button(ctx, 'Generate LTC', 140 * scale, 0) then
    generate_selected()
    -- Refresh regions after generation
    state.regions = build_region_table(collect_regions())
  end
  if not can_generate then
    ImGui.EndDisabled(ctx)
  end
  ImGui.SameLine(ctx, 0, 16)
  ImGui.TextColored(ctx, C.dim,
    string.format("%d of %d regions selected", n_selected, n_regions))

  ImGui.End(ctx)
  return open
end

-- ── Main loop ──────────────────────────────────────────────────────────────

local function loop()
  local success, result = pcall(draw_ui)
  if not success then
    reaper.MB("UI Error: " .. tostring(result), "ReaTC — Regions to LTC", 0)
    return
  end
  if result then
    reaper.defer(loop)
  end
end

loop()
