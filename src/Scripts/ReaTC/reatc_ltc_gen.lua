-- ReaTC LTC Generator - Create LTC media items per region

return function(core)
  local M = {}
  local s = core.state

  -- Parse timecode string "HH:MM:SS:FF" to components
  local function parse_tc(tc_str)
    -- Ensure we have a string
    if type(tc_str) ~= "string" then
      tc_str = "00:00:00:00"
    end
    
    local h, m, s, f = tc_str:match("^(%d+):(%d+):(%d+):(%d+)$")
    if h then
      return tonumber(h), tonumber(m), tonumber(s), tonumber(f)
    end
    return 0, 0, 0, 0
  end

  -- Format timecode as "HH:MM:SS:FF"
  local function format_tc(h, m, s, f)
    return string.format("%02d:%02d:%02d:%02d", h, m, s, f)
  end

  -- Convert seconds to timecode with offset
  local function seconds_to_tc_with_offset(pos, offset_h, offset_m, offset_s, offset_f, fr_type)
    local h, m, s, f = core.seconds_to_timecode(pos, fr_type)
    
    -- Add offset
    local fps = core.FPS_INT[fr_type + 1]
    f = f + offset_f
    if f >= fps then f = f - fps; s = s + 1 end
    
    s = s + offset_s
    if s >= 60 then s = s - 60; m = m + 1 end
    
    m = m + offset_m
    if m >= 60 then m = m - 60; h = h + 1 end
    
    h = (h + offset_h) % 24
    
    return h, m, s, f
  end

  -- Get or set region offset from project extended data
  function M.get_region_offset(region_idx)
    local key = string.format("ReaTC_Region_%d_Offset", region_idx)
    local offset = reaper.GetProjExtState(0, "ReaTC", key)
    if offset == "" or offset == nil or offset == 0 then
      return "00:00:00:00"
    end
    -- Ensure it's always a string
    return tostring(offset)
  end

  function M.set_region_offset(region_idx, offset_str)
    local key = string.format("ReaTC_Region_%d_Offset", region_idx)
    reaper.SetProjExtState(0, "ReaTC", key, offset_str)
  end

  -- Get all regions in the project
  function M.get_regions()
    local regions = {}
    local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
    
    local idx = 0
    while true do
      local retval, isrgn, pos, rgnend, name, markrgnindexnumber = 
        reaper.EnumProjectMarkers(idx)
      
      if retval == 0 then break end
      
      if isrgn then
        table.insert(regions, {
          index = markrgnindexnumber,
          start_pos = pos,
          end_pos = rgnend,
          name = name,
          offset = M.get_region_offset(markrgnindexnumber)
        })
      end
      
      idx = idx + 1
    end
    
    return regions
  end

  -- Create or get LTC output track
  function M.get_or_create_ltc_track()
    -- Look for existing track named "ReaTC LTC"
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
      local track = reaper.GetTrack(0, i)
      local _, name = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
      if name == "ReaTC LTC" then
        return track
      end
    end
    
    -- Create new track
    reaper.InsertTrackAtIndex(track_count, false)
    local track = reaper.GetTrack(0, track_count)
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "ReaTC LTC", true)
    
    -- Disable master/parent send
    reaper.SetMediaTrackInfo_Value(track, "B_MAINSEND", 0)
    
    return track
  end

  -- Generate LTC items for all regions
  function M.generate_ltc_items()
    local regions = M.get_regions()
    
    if #regions == 0 then
      reaper.MB("No regions found in project.\n\nCreate regions first, then generate LTC items.", 
                "ReaTC LTC Generator", 0)
      return false
    end
    
    if not s.python_bin then
      reaper.MB("Python 3 not found.\n\nPython is required to generate LTC audio.", 
                "ReaTC LTC Generator", 0)
      return false
    end
    
    reaper.Undo_BeginBlock()
    
    local track = M.get_or_create_ltc_track()
    local fr_type = s.framerate_type
    local fps = core.FPS_VAL[fr_type + 1]
    
    -- Clear existing items on LTC track
    local ret = reaper.MB("Clear existing items on \\\"ReaTC LTC\\\" track?", 
                          "ReaTC LTC Generator", 4)
    if ret == 6 then  -- Yes
      local item_count = reaper.CountTrackMediaItems(track)
      for i = item_count - 1, 0, -1 do
        local item = reaper.GetTrackMediaItem(track, i)
        reaper.DeleteTrackMediaItem(track, item)
      end
    end
    
    -- Create temp directory for LTC audio files
    local temp_dir = reaper.GetProjectPath("") .. "/ReaTC_LTC_Temp/"
    os.execute((core.is_win and "mkdir " or "mkdir -p ") .. "\"" .. temp_dir .. "\"")
    
    -- Generate LTC item for each region
    for _, rgn in ipairs(regions) do
      local offset_h, offset_m, offset_s, offset_f = parse_tc(rgn.offset)
      
      -- Calculate start timecode with offset
      local start_h, start_m, start_s, start_f = 
        seconds_to_tc_with_offset(rgn.start_pos, offset_h, offset_m, offset_s, offset_f, fr_type)
      
      local duration = rgn.end_pos - rgn.start_pos
      local tc_name = format_tc(start_h, start_m, start_s, start_f)
      local safe_name = tc_name:gsub(":", "-")
      local wav_file = temp_dir .. "LTC_" .. safe_name .. ".wav"
      
      -- Generate LTC audio using Python script
      local q = core.is_win and ('\"' .. s.python_bin .. '\"') or s.python_bin
      local cmd = string.format(
        '%s \"%s\" --generate \"%s\" %d %d %d %d %d %.3f %s',
        q, core.py_ltcout, wav_file, 
        start_h, start_m, start_s, start_f, fr_type, duration,
        core.dev_null
      )
      
      local result = os.execute(cmd)
      
      if result == 0 or result == true then
        -- Import audio file as media item
        local item = reaper.AddMediaItemToTrack(track)
        reaper.SetMediaItemPosition(item, rgn.start_pos, false)
        reaper.SetMediaItemLength(item, duration, false)
        
        local take = reaper.AddTakeToMediaItem(item)
        local source = reaper.PCM_Source_CreateFromFile(wav_file)
        
        if source then
          reaper.SetMediaItemTake_Source(take, source)
          -- Note: Don't destroy the source - the take now owns it
          
          -- Set take name
          local region_label = rgn.name ~= "" and (" - " .. rgn.name) or ""
          reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", 
            "LTC " .. tc_name .. region_label, true)
          
          -- Update item color
          reaper.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", 
            reaper.ColorToNative(100, 150, 255) | 0x1000000)
        end
      end
    end
    
    reaper.Undo_EndBlock("ReaTC: Generate LTC items from regions", -1)
    reaper.UpdateArrange()
    
    reaper.MB(string.format("Generated %d LTC item(s) on \\\"ReaTC LTC\\\" track.", #regions),
              "ReaTC LTC Generator", 0)
    
    return true
  end

  return M
end
