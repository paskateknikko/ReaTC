-- ReaTC LTC decoder — JSFX bridge
--
-- Manages the reatc_ltc.jsfx plugin on the selected LTC track.
-- The JSFX decodes LTC audio in real-time and writes results to
-- gmem["ReaTC_LTC"] and to its output sliders.
-- This module reads those sliders via TrackFX_GetParam.
-- @noindex
-- @version {{VERSION}}

return function(core)
  local M = {}
  local s = core.state

  -- JSFX identifier (path relative to REAPER Effects directory, no extension)
  local JSFX_NAME = "JS: ReaTC/reatc_ltc"

  -- Slider parameter indices (0-based, matching the .jsfx slider definitions)
  local SL_HOURS   = 0   -- slider1  output
  local SL_MINUTES = 1   -- slider2  output
  local SL_SECONDS = 2   -- slider3  output
  local SL_FRAMES  = 3   -- slider4  output
  local SL_LOCKED  = 4   -- slider5  output
  local SL_SEQ     = 5   -- slider6  output
  local SL_FPS     = 6   -- slider7  input (Lua writes framerate type)
  local SL_THRESH  = 7   -- slider8  input (Lua writes threshold dB)
  local SL_PEAK    = 8   -- slider9  output

  -- Track last-written config to avoid triggering @slider unnecessarily
  local _last_fps    = nil
  local _last_thresh = nil

  local function find_jsfx(track)
    local n = reaper.TrackFX_GetCount(track)
    for i = 0, n - 1 do
      local _, name = reaper.TrackFX_GetFXName(track, i, "")
      if name and name:find("ReaTC LTC Decoder", 1, true) then
        return i
      end
    end
    return nil
  end

  local function ensure_jsfx(track)
    local fx = find_jsfx(track)
    if fx then return fx end
    local idx = reaper.TrackFX_AddByName(track, JSFX_NAME, false, -1)
    return idx >= 0 and idx or nil
  end

  -- Called once per Lua frame when LTC is enabled and a track is selected.
  function M.update_jsfx()
    local track = s.ltc_track
    if not track then return end

    -- Validate track pointer (becomes stale if track deleted)
    if not reaper.ValidatePtr(track, "MediaTrack*") then
      s.ltc_track = nil
      s.ltc_fx_idx = nil
      return
    end

    -- Lazily find or insert the JSFX
    if not s.ltc_fx_idx then
      s.ltc_fx_idx = ensure_jsfx(track)
      _last_fps    = nil   -- force param push after insertion
      _last_thresh = nil
    end

    local fx = s.ltc_fx_idx
    if not fx then return end

    -- Push configuration to JSFX only when it changes
    -- (avoids triggering @slider on every frame)
    if s.framerate_type ~= _last_fps or s.threshold_db ~= _last_thresh then
      reaper.TrackFX_SetParam(track, fx, SL_FPS,    s.framerate_type)
      reaper.TrackFX_SetParam(track, fx, SL_THRESH, s.threshold_db)
      _last_fps    = s.framerate_type
      _last_thresh = s.threshold_db
    end

    -- Read peak level for UI display
    local peak = reaper.TrackFX_GetParam(track, fx, SL_PEAK)
    s.peak_level = peak or 0

    -- Read locked state
    local locked = reaper.TrackFX_GetParam(track, fx, SL_LOCKED)
    if not locked or locked < 0.5 then
      -- JSFX reports no lock; expire after 0.5 s of silence
      if s.tc_valid and reaper.time_precise() - s.last_valid_time > 0.5 then
        s.tc_valid = false
      end
      return
    end

    -- Read sequence counter to detect new decoded frames
    local seq = reaper.TrackFX_GetParam(track, fx, SL_SEQ)
    if seq and seq ~= s.ltc_seq then
      s.ltc_seq = seq
      local h   = reaper.TrackFX_GetParam(track, fx, SL_HOURS)
      local m   = reaper.TrackFX_GetParam(track, fx, SL_MINUTES)
      local sec = reaper.TrackFX_GetParam(track, fx, SL_SECONDS)
      local f   = reaper.TrackFX_GetParam(track, fx, SL_FRAMES)
      s.tc_h, s.tc_m, s.tc_s, s.tc_f =
        math.floor(h), math.floor(m), math.floor(sec), math.floor(f)
      s.tc_type       = s.framerate_type
      s.tc_valid      = true
      s.last_valid_time = reaper.time_precise()
    elseif s.tc_valid and reaper.time_precise() - s.last_valid_time > 0.5 then
      s.tc_valid = false
    end
  end

  -- Called when the selected LTC track changes so we re-discover the JSFX.
  function M.on_track_changed()
    s.ltc_fx_idx = nil
    s.ltc_seq    = -1
    s.tc_valid   = false
    s.peak_level = 0
    _last_fps    = nil
    _last_thresh = nil
  end

  -- Legacy no-op kept so call sites in ReaTC.lua/reatc_ui.lua don't break.
  function M.destroy_accessor() end

  return M
end
