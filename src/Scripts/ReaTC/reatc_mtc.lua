-- ReaTC MTC — JSFX bridge for MIDI Timecode output
--
-- Manages the "ReaTC MTC" track and reatc_mtc.jsfx plugin.
-- Writes play state and framerate to gmem so the JSFX can emit
-- sample-accurate MIDI quarter-frame messages.
--
-- gmem slots (shared namespace "ReaTC_LTC", indices 10-16):
--   [10] MTC_PLAY_STATE   Lua -> JSFX   0=stop 1=play
--   [11] MTC_FRAMERATE    Lua -> JSFX   0=24 1=25 2=29.97DF 3=30
--   [12] MTC_SEND_FF      Lua -> JSFX   1=send full-frame SysEx next @block
--   [13] MTC_FF_H         Lua -> JSFX   full-frame target hours
--   [14] MTC_FF_M         Lua -> JSFX   full-frame target minutes
--   [15] MTC_FF_S         Lua -> JSFX   full-frame target seconds
--   [16] MTC_FF_F         Lua -> JSFX   full-frame target frames
-- @noindex
-- @version {{VERSION}}

return function(core)
  local M = {}
  local s = core.state

  -- JSFX identifier (path relative to REAPER Effects directory, no extension)
  local JSFX_NAME  = "JS: ReaTC/reatc_mtc"
  local TRACK_NAME = "ReaTC MTC"

  -- gmem slot indices (must match reatc_mtc.jsfx @init declarations)
  local GMEM_PLAY    = 10
  local GMEM_FPS     = 11
  local GMEM_SEND_FF = 12
  local GMEM_FF_H    = 13
  local GMEM_FF_M    = 14
  local GMEM_FF_S    = 15
  local GMEM_FF_F    = 16

  -- Module-local state
  local _last_play_state = -1   -- last play state written to gmem
  local _last_fps        = nil  -- last framerate type written to gmem
  local _mtc_fx_idx      = nil  -- cached FX chain index

  -- ── Track helpers ───────────────────────────────────────────────────────────

  local function find_track_by_name(name)
    local n = reaper.CountTracks(0)
    for i = 0, n - 1 do
      local tr = reaper.GetTrack(0, i)
      if tr then
        local _, nm = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if nm == name then return tr end
      end
    end
    return nil
  end

  local function find_jsfx(track)
    local n = reaper.TrackFX_GetCount(track)
    for i = 0, n - 1 do
      local _, name = reaper.TrackFX_GetFXName(track, i, "")
      if name and name:find("ReaTC MTC Generator", 1, true) then
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

  -- ── Public API ──────────────────────────────────────────────────────────────

  -- Ensure the "ReaTC MTC" track exists, creating it if needed.
  -- Stores the track GUID in state for persistence across reorders.
  function M.ensure_track()
    -- 1. Try GUID lookup
    if s.mtc_track_guid then
      local tr = core.get_track_by_guid(s.mtc_track_guid)
      if tr and reaper.ValidatePtr(tr, "MediaTrack*") then
        -- Confirm name still matches (user might have renamed)
        local _, nm = reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
        if nm == TRACK_NAME then
          s.mtc_track = tr
          return tr
        end
      end
    end

    -- 2. Scan by name
    local tr = find_track_by_name(TRACK_NAME)
    if tr then
      s.mtc_track      = tr
      s.mtc_track_guid = core.get_track_guid(tr)
      core.save_settings()
      return tr
    end

    -- 3. Auto-create at the end of the track list
    reaper.Undo_BeginBlock2(0)
    local idx = reaper.CountTracks(0)
    reaper.InsertTrackAtIndex(idx, true)
    tr = reaper.GetTrack(0, idx)
    if not tr then
      reaper.Undo_EndBlock2(0, "ReaTC: Create MTC track", -1)
      s.mtc_error = "Failed to create MTC track"
      return nil
    end

    reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", TRACK_NAME, true)

    -- Mute the track — it produces no audio; we only want its MIDI output
    reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", 1)

    reaper.Undo_EndBlock2(0, "ReaTC: Create MTC track", -1)

    s.mtc_track      = tr
    s.mtc_track_guid = core.get_track_guid(tr)
    s.mtc_error      = nil
    core.save_settings()
    return tr
  end

  -- Called every defer frame when MTC is enabled.
  -- Validates track, lazily inserts JSFX, writes gmem.
  function M.update()
    if not s.mtc_enabled then return end

    -- Validate track handle (becomes stale if track deleted)
    if s.mtc_track and not reaper.ValidatePtr(s.mtc_track, "MediaTrack*") then
      s.mtc_track  = nil
      _mtc_fx_idx  = nil
      _last_play_state = -1
    end

    if not s.mtc_track then
      M.ensure_track()
    end
    if not s.mtc_track then return end

    -- Lazily insert JSFX
    if not _mtc_fx_idx then
      _mtc_fx_idx  = ensure_jsfx(s.mtc_track)
      s.mtc_fx_idx = _mtc_fx_idx
      _last_fps    = nil   -- force gmem write after insertion
      _last_play_state = -1
    end
    if not _mtc_fx_idx then return end

    -- Determine current play state and TC
    local play_state = (reaper.GetPlayState() & 1) == 1 and 1 or 0

    -- Write framerate to gmem when it changes
    if s.framerate_type ~= _last_fps then
      reaper.gmem_write(GMEM_FPS, s.framerate_type)
      _last_fps = s.framerate_type
    end

    -- Detect play-state transitions
    if play_state ~= _last_play_state then
      -- Write full-frame TC for the locate message
      local h, m, sec, f = core.get_active_tc()
      reaper.gmem_write(GMEM_FF_H, h)
      reaper.gmem_write(GMEM_FF_M, m)
      reaper.gmem_write(GMEM_FF_S, sec)
      reaper.gmem_write(GMEM_FF_F, f)
      reaper.gmem_write(GMEM_SEND_FF, 1)

      _last_play_state = play_state
    end

    -- Always keep play state up-to-date for the JSFX
    reaper.gmem_write(GMEM_PLAY, play_state)
  end

  -- Called when MTC is disabled. Stops QF output immediately.
  function M.on_disable()
    reaper.gmem_write(GMEM_PLAY,    0)
    reaper.gmem_write(GMEM_SEND_FF, 0)
    _last_play_state = -1
    _last_fps        = nil
    _mtc_fx_idx      = nil
    s.mtc_fx_idx     = nil
  end

  return M
end
