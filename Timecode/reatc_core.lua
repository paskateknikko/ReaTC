--- ReaTC — https://github.com/paskateknikko/ReaTC
-- Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
--
--- ReaTC core module: constants, shared state, config persistence, and timecode math.
-- All other modules depend on this. The `state` table is shared across the entire
-- ReaTC runtime — UI, outputs, and the main loop all read/write it.
-- @module reatc_core
-- @noindex
-- @version 1.1.0

local M = {}

M.VERSION = "1.1.0"
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
  "py",                         -- Windows Python Launcher (recommended)
  "C:\\Python313\\python.exe",
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

-- Source IDs (matching JSFX active_source values)
M.SRC_NONE     = 0
M.SRC_LTC      = 1
M.SRC_MTC      = 2
M.SRC_TIMELINE = 3

M.SRC_NAMES = { [0] = "None", [1] = "LTC", [2] = "MTC", [3] = "Timeline" }

-- gmem indices — must match reatc_tc.jsfx @init constants
M.GMEM_TC_HOUR         = 0
M.GMEM_TC_MIN          = 1
M.GMEM_TC_SEC          = 2
M.GMEM_TC_FRAME        = 3
M.GMEM_TC_FRAMERATE    = 4
M.GMEM_TC_VALID        = 6
M.GMEM_TC_WRITE_COUNTER = 7
M.GMEM_SCRIPT_ALIVE    = 8
M.GMEM_ACTIVE_SOURCE   = 17
M.GMEM_TC_OFFSET_H     = 20
M.GMEM_TC_OFFSET_M     = 21
M.GMEM_TC_OFFSET_S     = 22
M.GMEM_TC_OFFSET_F     = 23
M.GMEM_TC_OFFSET_SIGN  = 24

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

  -- OSC
  osc_enabled      = false,
  osc_ip           = "127.0.0.1",
  osc_port         = 9000,
  osc_address      = "/tc",
  osc_proc         = nil,
  osc_error        = nil,
  last_osc_time    = 0,
  osc_packets_sent = 0,

  -- Active TC (read from gmem, written by JSFX)
  tc_h = 0, tc_m = 0, tc_s = 0, tc_f = 0,
  tc_valid       = false,
  active_source  = 0,  -- SRC_NONE/LTC/MTC/TIMELINE

  -- JSFX detection
  jsfx_detected     = false,
  last_write_counter = -1,
  jsfx_stale_count   = 0,

  -- TC Offset
  tc_offset_h        = 0,
  tc_offset_m        = 0,
  tc_offset_s        = 0,
  tc_offset_f        = 0,
  tc_offset_negative = false,

  -- UI state
  show_settings  = false,
  last_win_w     = M.MIN_WIN_W,
  last_win_h     = M.MIN_WIN_H,
}


--- Search for a working Python 3 interpreter.
-- Tries each candidate in order, returns the first that responds to `--version`.
-- @return string|nil Python binary path, or nil if not found
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

--- Read active timecode from gmem shared memory (written by the JSFX).
-- Updates `state.tc_h/m/s/f`, `state.tc_valid`, `state.active_source`,
-- `state.framerate_type`, and `state.jsfx_detected`.
function M.update_tc_from_gmem()
  local s = M.state
  s.tc_h = math.floor(reaper.gmem_read(M.GMEM_TC_HOUR))
  s.tc_m = math.floor(reaper.gmem_read(M.GMEM_TC_MIN))
  s.tc_s = math.floor(reaper.gmem_read(M.GMEM_TC_SEC))
  s.tc_f = math.floor(reaper.gmem_read(M.GMEM_TC_FRAME))
  s.framerate_type = math.floor(reaper.gmem_read(M.GMEM_TC_FRAMERATE))
  s.tc_valid = reaper.gmem_read(M.GMEM_TC_VALID) > 0.5
  s.active_source = math.floor(reaper.gmem_read(M.GMEM_ACTIVE_SOURCE))

  -- JSFX detection: TC_WRITE_COUNTER increments every @block
  local wc = math.floor(reaper.gmem_read(M.GMEM_TC_WRITE_COUNTER))
  if wc ~= s.last_write_counter then
    s.last_write_counter = wc
    s.jsfx_stale_count = 0
    s.jsfx_detected = true
  else
    s.jsfx_stale_count = s.jsfx_stale_count + 1
    if s.jsfx_stale_count > 30 then  -- ~1 second at 30 fps defer
      s.jsfx_detected = false
    end
  end
end

--- Get the current active timecode values.
-- @return number hours (0-23)
-- @return number minutes (0-59)
-- @return number seconds (0-59)
-- @return number frames (0-fps)
-- @return string source name ("None", "LTC", "MTC", or "Timeline")
function M.get_active_tc()
  local s = M.state
  return s.tc_h, s.tc_m, s.tc_s, s.tc_f, M.SRC_NAMES[s.active_source] or "None"
end

--- Validate an IPv4 address string.
-- @param ip string address in "aaa.bbb.ccc.ddd" format
-- @return boolean true if valid
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

--- Convert a time position in seconds to HH:MM:SS:FF timecode.
-- Uses integer math for drop-frame (29.97fps) to avoid float drift.
-- @param pos number time position in seconds (clamped to >= 0)
-- @param fr_type number framerate type index (0=24, 1=25, 2=29.97DF, 3=30)
-- @return number hours, number minutes, number seconds, number frames
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

-- Settings key constants
local SK = {
  DEST_IP           = "dest_ip",
  ARTNET_ENABLED    = "artnet_enabled",
  OSC_ENABLED       = "osc_enabled",
  OSC_IP            = "osc_ip",
  OSC_PORT          = "osc_port",
  OSC_ADDRESS       = "osc_address",
  TC_OFFSET_H       = "tc_offset_h",
  TC_OFFSET_M       = "tc_offset_m",
  TC_OFFSET_S       = "tc_offset_s",
  TC_OFFSET_F       = "tc_offset_f",
  TC_OFFSET_NEGATIVE = "tc_offset_negative",
}

--- Load all settings from REAPER ExtState and apply to `state`.
-- Also cleans up legacy settings keys from older versions.
function M.load_settings()
  local function gets(k)
    local v = reaper.GetExtState(M.EXT_SECTION, k)
    return v ~= "" and v or nil
  end
  local s = M.state
  local loaded_ip = gets(SK.DEST_IP)
  s.dest_ip = (loaded_ip and M.is_valid_ipv4(loaded_ip)) and loaded_ip or s.dest_ip
  s.artnet_enabled  = gets(SK.ARTNET_ENABLED) == "true"
  s.osc_enabled    = gets(SK.OSC_ENABLED) == "true"
  local loaded_osc_ip = gets(SK.OSC_IP)
  s.osc_ip         = (loaded_osc_ip and M.is_valid_ipv4(loaded_osc_ip)) and loaded_osc_ip or s.osc_ip
  s.osc_port       = tonumber(gets(SK.OSC_PORT)) or 9000
  s.osc_address    = gets(SK.OSC_ADDRESS) or "/tc"
  s.tc_offset_h        = tonumber(gets(SK.TC_OFFSET_H)) or 0
  s.tc_offset_m        = tonumber(gets(SK.TC_OFFSET_M)) or 0
  s.tc_offset_s        = tonumber(gets(SK.TC_OFFSET_S)) or 0
  s.tc_offset_f        = tonumber(gets(SK.TC_OFFSET_F)) or 0
  s.tc_offset_negative = gets(SK.TC_OFFSET_NEGATIVE) == "true"

  -- Clean up legacy settings (framerate now owned by JSFX, old track-management keys)
  reaper.DeleteExtState(M.EXT_SECTION, "framerate_type", true)
  reaper.DeleteExtState(M.EXT_SECTION, "ltc_enabled", true)
  reaper.DeleteExtState(M.EXT_SECTION, "ltc_track_guid", true)
  reaper.DeleteExtState(M.EXT_SECTION, "ltc_fallback", true)
  reaper.DeleteExtState(M.EXT_SECTION, "threshold_db", true)
  reaper.DeleteExtState(M.EXT_SECTION, "mtc_enabled", true)
  reaper.DeleteExtState(M.EXT_SECTION, "mtc_track_guid", true)
end

--- Persist all settings to REAPER ExtState.
function M.save_settings()
  local s = M.state
  local function sets(k, v) reaper.SetExtState(M.EXT_SECTION, k, tostring(v), true) end
  sets(SK.DEST_IP,           s.dest_ip)
  sets(SK.ARTNET_ENABLED,    s.artnet_enabled)
  sets(SK.OSC_ENABLED,       s.osc_enabled)
  sets(SK.OSC_IP,            s.osc_ip)
  sets(SK.OSC_PORT,          s.osc_port)
  sets(SK.OSC_ADDRESS,       s.osc_address)
  sets(SK.TC_OFFSET_H,       s.tc_offset_h)
  sets(SK.TC_OFFSET_M,       s.tc_offset_m)
  sets(SK.TC_OFFSET_S,       s.tc_offset_s)
  sets(SK.TC_OFFSET_F,       s.tc_offset_f)
  sets(SK.TC_OFFSET_NEGATIVE, s.tc_offset_negative)
end

return M
