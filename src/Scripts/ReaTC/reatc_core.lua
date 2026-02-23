-- ReaTC core: constants, state, config, and timecode helpers
-- @noindex
-- @version {{VERSION}}

local M = {}

M.VERSION = "{{VERSION}}"
M.EXT_SECTION = "ReaTC"
M.MIN_WIN_W, M.MIN_WIN_H = 440, 240

-- Frame rate type indices (0-based, matching Art-Net spec)
M.FR_FILM  = 0  -- 24 fps
M.FR_EBU   = 1  -- 25 fps
M.FR_DF    = 2  -- 29.97 fps drop-frame
M.FR_SMPTE = 3  -- 30 fps

M.FR_NAMES = { "24fps (Film)", "25fps (EBU)", "29.97DF", "30fps (SMPTE)" }
M.FPS_VAL  = { 24, 25, 29.97, 30 }  -- index 1..4
M.FPS_INT  = { 24, 25, 30,    30 }  -- integer frame count

M.PYTHON_CANDIDATES = {
  "python3", "python",
  "/usr/bin/python3",
  "/usr/local/bin/python3",
  "/opt/homebrew/bin/python3",  -- macOS ARM (Homebrew)
  "C:\\Python312\\python.exe",
  "C:\\Python311\\python.exe",
  "C:\\Python310\\python.exe",
}

-- Script / helper file paths
M.script_path = nil

do
  local info = debug.getinfo(1, "S")
  M.script_path = info.source:match("@(.+[\\/])") or ""
end

M.py_artnet = M.script_path .. "reatc_artnet.py"
M.py_osc    = M.script_path .. "reatc_osc.py"

M.is_win = reaper.GetOS():find("Win") ~= nil
M.dev_null = M.is_win and "2>NUL" or "2>/dev/null"

-- State
M.state = {
  -- Python
  python_bin   = nil,
  python_error = nil,

  -- Art-Net
  artnet_enabled   = false,
  artnet_proc      = nil,
  dest_ip          = "2.0.0.1",
  framerate_type   = M.FR_EBU,
  packets_sent     = 0,
  artnet_error     = nil,
  last_artnet_time = 0,

  -- MTC
  mtc_enabled      = false,
  mtc_track_guid   = nil,    -- GUID of "ReaTC MTC" track (persists across reorder)
  mtc_track        = nil,    -- MediaTrack handle
  mtc_fx_idx       = nil,    -- FX chain index of reatc_mtc.jsfx
  mtc_error        = nil,

  -- OSC
  osc_enabled   = false,
  osc_ip        = "127.0.0.1",
  osc_port      = 9000,
  osc_address   = "/tc",
  osc_proc      = nil,
  osc_error     = nil,
  last_osc_time = 0,

  -- LTC decoder configuration
  ltc_enabled    = false,
  ltc_track_guid = nil,      -- track GUID (persists across reorder/add/delete)
  ltc_track      = nil,      -- MediaTrack handle
  threshold_db   = -24,
  ltc_fallback   = true,     -- auto-fallback to timeline when not locked

  -- UI state
  show_settings  = false,
  last_win_w     = M.MIN_WIN_W,
  last_win_h     = M.MIN_WIN_H,

  -- Signal level monitoring (populated from JSFX slider9)
  peak_level     = 0,

  -- JSFX bridge state
  ltc_fx_idx     = nil,      -- FX chain index of reatc_ltc.jsfx on the LTC track
  ltc_seq        = -1,       -- last seen sequence counter from JSFX

  -- Decoded LTC timecode
  tc_h = 0, tc_m = 0, tc_s = 0, tc_f = 0, tc_type = M.FR_EBU,
  tc_valid          = false,
  last_valid_time   = 0,

  -- Transport timecode (used when LTC not active)
  tr_h = 0, tr_m = 0, tr_s = 0, tr_f = 0,
}


-- Python detection
function M.find_python()
  for _, cmd in ipairs(M.PYTHON_CANDIDATES) do
    local quoted = M.is_win and ('"' .. cmd .. '"') or cmd
    local h = io.popen(quoted .. ' --version 2>&1')
    if h then
      local out = h:read("*a"); h:close()
      if out and out:match("Python 3") then return cmd end
    end
  end
  return nil
end

-- Timecode source selection
function M.get_active_tc()
  local s = M.state
  local use_ltc = s.ltc_enabled and s.ltc_track ~= nil and s.tc_valid

  if use_ltc then
    return s.tc_h, s.tc_m, s.tc_s, s.tc_f, "LTC"
  elseif s.ltc_fallback or not s.ltc_enabled then
    return s.tr_h, s.tr_m, s.tr_s, s.tr_f, "Timeline"
  else
    return s.tc_h, s.tc_m, s.tc_s, s.tc_f, "Hold"
  end
end

-- Validate IPv4 address format (aaa.bbb.ccc.ddd where each octet is 0-255)
function M.is_valid_ipv4(ip)
  if not ip or type(ip) ~= "string" then return false end
  local octets = {}
  for octet in ip:gmatch("([^%.]+)") do
    local n = tonumber(octet)
    if not n or n < 0 or n > 255 or not octet:match("^%d+$") then
      return false
    end
    octets[#octets + 1] = n
  end
  return #octets == 4
end

-- Get track GUID (unique identifier that persists across reorder/add/delete)
function M.get_track_guid(track)
  if not track then return nil end
  local guid = reaper.GetTrackGUID(track)
  return guid ~= "" and guid or nil
end

-- Get track by GUID (with optional fallback to index if GUID not found)
function M.get_track_by_guid(guid, fallback_idx)
  if not guid then return reaper.GetTrack(0, fallback_idx or 0) end
  local track_count = reaper.CountTracks(0)
  for i = 0, track_count - 1 do
    local tr = reaper.GetTrack(0, i)
    if tr and M.get_track_guid(tr) == guid then
      return tr
    end
  end
  -- GUID not found; return fallback track if provided
  return fallback_idx and reaper.GetTrack(0, fallback_idx) or nil
end

function M.seconds_to_timecode(pos, fr_type)
  pos = math.max(0, pos)  -- clamp negative play positions to zero
  local fps = M.FPS_VAL[fr_type + 1]
  if fps == 29.97 then
    local total = math.floor(pos * 30)
    local d  = math.floor(total / 17982)
    local mm = total % 17982
    local tf = total + 18 * d + 2 * math.max(0, math.floor((mm - 2) / 1798))
    return math.floor(tf / 108000) % 24,
           math.floor(tf / 1800) % 60,
           math.floor(tf / 30) % 60,
           tf % 30
  else
    local int_fps = M.FPS_INT[fr_type + 1]
    local total   = math.floor(pos * int_fps)
    local frames  = total % int_fps
    local ts      = math.floor(total / int_fps)
    return math.floor(ts / 3600) % 24,
           math.floor(ts / 60) % 60,
           ts % 60,
           frames
  end
end

function M.update_transport_tc()
  local pos = reaper.GetPlayPosition()
  local h, m, s, f = M.seconds_to_timecode(pos, M.state.framerate_type)
  M.state.tr_h, M.state.tr_m, M.state.tr_s, M.state.tr_f = h, m, s, f
end

-- Config persistence
function M.load_settings()
  local function gets(k)
    local v = reaper.GetExtState(M.EXT_SECTION, k)
    return v ~= "" and v or nil
  end
  local s = M.state
  local loaded_ip = gets("dest_ip")
  s.dest_ip = (loaded_ip and M.is_valid_ipv4(loaded_ip)) and loaded_ip or s.dest_ip
  s.framerate_type = tonumber(gets("framerate_type")) or s.framerate_type
  s.artnet_enabled  = gets("artnet_enabled") == "true"
  s.mtc_enabled     = gets("mtc_enabled")   == "true"
  s.mtc_track_guid  = gets("mtc_track_guid")
  s.ltc_enabled     = gets("ltc_enabled")   == "true"
  s.ltc_track_guid = gets("ltc_track_guid")  -- GUID-based track persistence
  s.threshold_db   = tonumber(gets("threshold_db")) or -24
  s.ltc_fallback   = gets("ltc_fallback") ~= "false"  -- default true
  s.osc_enabled    = gets("osc_enabled") == "true"
  local loaded_osc_ip = gets("osc_ip")
  s.osc_ip         = (loaded_osc_ip and M.is_valid_ipv4(loaded_osc_ip)) and loaded_osc_ip or s.osc_ip
  s.osc_port       = tonumber(gets("osc_port")) or 9000
  s.osc_address    = gets("osc_address") or "/tc"
  -- Resolve GUIDs to track handles
  if s.ltc_track_guid then
    s.ltc_track = M.get_track_by_guid(s.ltc_track_guid)
  end
  if s.mtc_track_guid then
    s.mtc_track = M.get_track_by_guid(s.mtc_track_guid)
  end
end

function M.save_settings()
  local s = M.state
  local function sets(k, v) reaper.SetExtState(M.EXT_SECTION, k, tostring(v), true) end
  sets("dest_ip",        s.dest_ip)
  sets("framerate_type", s.framerate_type)
  sets("artnet_enabled",  s.artnet_enabled)
  sets("mtc_enabled",     s.mtc_enabled)
  sets("mtc_track_guid",  s.mtc_track_guid or "")
  sets("ltc_enabled",     s.ltc_enabled)
  sets("ltc_track_guid", s.ltc_track_guid or "")
  sets("threshold_db",   s.threshold_db)
  sets("ltc_fallback",   s.ltc_fallback)
  sets("osc_enabled",    s.osc_enabled)
  sets("osc_ip",         s.osc_ip)
  sets("osc_port",       s.osc_port)
  sets("osc_address",    s.osc_address)
end

return M
