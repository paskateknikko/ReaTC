-- ReaTC bake: auto-create LTC audio items from project regions
-- @noindex
-- @version {{VERSION}}

return function(core)
  local M = {}

  M.py_ltcgen  = core.script_path .. "reatc_ltcgen.py"
  local TRACK_NAME = "LTC [rendered]"

  -- ── Helpers ──────────────────────────────────────────────────────────────

  local function get_or_create_track()
    for i = 0, reaper.CountTracks(0) - 1 do
      local tr = reaper.GetTrack(0, i)
      local _, nm = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
      if nm == TRACK_NAME then return tr end
    end
    local idx = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(idx, false)
    local tr = reaper.GetTrack(0, idx)
    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", TRACK_NAME, true)
    return tr
  end

  local function collect_regions()
    local regions = {}
    local total = reaper.CountProjectMarkers(0)
    for i = 0, total - 1 do
      local _, isrgn, pos, rgnend, name, rgn_idx = reaper.EnumProjectMarkers(0, i)
      if isrgn and rgnend > pos then
        regions[#regions + 1] = {
          pos    = pos,
          endpos = rgnend,
          name   = name or "",
          index  = rgn_idx,
        }
      end
    end
    return regions
  end

  -- Sanitise a string for use as a filename component
  local function safe_filename(str, max_len)
    return str:gsub('[^%w%-_ ]', '_'):sub(1, max_len or 40)
  end

  -- ── Public API ────────────────────────────────────────────────────────────

  function M.bake_regions()
    if not core.state.python_bin then
      reaper.MB(
        "Python 3 is required to generate LTC audio.\n\n" ..
        "Check the Art-Net / OSC section in ReaTC settings.",
        "ReaTC — Bake LTC", 0)
      return
    end

    local regions = collect_regions()
    if #regions == 0 then
      reaper.MB(
        "No regions found in the project.\n\n" ..
        "Create regions on the REAPER timeline first (drag in the region lane).",
        "ReaTC — Bake LTC", 0)
      return
    end

    -- Confirm before potentially slow operation
    local fr_name = core.FR_NAMES[core.state.framerate_type + 1]
    local ret = reaper.MB(
      string.format(
        "Generate LTC audio items for %d region(s)?\n\n" ..
        "Frame rate: %s\n" ..
        "Destination track: '%s'\n\n" ..
        "Existing items on that track are not removed.\n" ..
        "This may take a moment for long regions.",
        #regions, fr_name, TRACK_NAME),
      "ReaTC — Bake LTC", 4)  -- 4 = Yes/No buttons
    if ret ~= 6 then return end  -- 6 = Yes

    -- Require a saved project (we need a directory for the WAV files)
    local proj_path = reaper.GetProjectPath("")
    if proj_path == "" then
      reaper.MB(
        "Please save the project before baking LTC.\n\n" ..
        "The WAV files will be placed in a 'ReaTC_LTC' sub-folder next to the project.",
        "ReaTC — Bake LTC", 0)
      return
    end

    local sep     = core.is_win and "\\" or "/"
    local ltc_dir = proj_path .. sep .. "ReaTC_LTC"

    -- Create output directory (silent if already exists)
    if core.is_win then
      os.execute('if not exist "' .. ltc_dir .. '" mkdir "' .. ltc_dir .. '"')
    else
      os.execute('mkdir -p "' .. ltc_dir .. '"')
    end

    local sample_rate = math.floor(reaper.GetSetProjectInfo(0, "SAMPLERATE", 0, false))
    if sample_rate <= 0 then sample_rate = 48000 end

    local q       = core.is_win and ('"' .. core.state.python_bin .. '"') or core.state.python_bin
    local fr_type = core.state.framerate_type
    local fps_val = core.FPS_VAL[fr_type + 1]

    local track    = get_or_create_track()
    local ok_count = 0
    local err_list = {}

    reaper.Undo_BeginBlock()

    for _, rgn in ipairs(regions) do
      local duration = rgn.endpos - rgn.pos

      -- Compute starting TC for this region
      local h, m, s, f = core.seconds_to_timecode(rgn.pos, fr_type)

      -- Number of LTC frames to generate (+1 safety so the WAV is never shorter)
      local n_frames = math.ceil(duration * fps_val) + 1

      -- Build a safe filename: ltc_<regionidx>_<name>.wav
      local label   = rgn.name ~= "" and rgn.name or ("region" .. rgn.index)
      local fname   = string.format("ltc_%d_%s.wav", rgn.index, safe_filename(label))
      local wav_path = ltc_dir .. sep .. fname

      -- Run the Python generator synchronously (blocking until done)
      local cmd = string.format('%s "%s" %d %d %d %d %d %d %d "%s" %s',
        q, M.py_ltcgen,
        fr_type, h, m, s, f,
        n_frames, sample_rate,
        wav_path,
        core.dev_null)

      os.execute(cmd)

      -- Load the generated WAV and insert as an item on the render track
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

    -- Result summary
    if ok_count == #regions then
      reaper.MB(
        string.format(
          "Done! Added %d LTC item(s) to track '%s'.\n\nFiles: %s",
          ok_count, TRACK_NAME, ltc_dir),
        "ReaTC — Bake LTC", 0)
    else
      reaper.MB(
        string.format(
          "%d/%d region(s) succeeded.\n\nFailed: %s\n\n" ..
          "Make sure Python 3 is accessible and the project folder is writable.",
          ok_count, #regions, table.concat(err_list, ", ")),
        "ReaTC — Bake LTC", 0)
    end
  end

  return M
end
