-- ReaTC — https://github.com/paskateknikko/ReaTC
-- Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
--
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

-- Read active TC from gmem (written by unified JSFX)
function M.update_tc_from_gmem()
  local s = M.state
  s.tc_h = math.floor(reaper.gmem_read(0))
  s.tc_m = math.floor(reaper.gmem_read(1))
  s.tc_s = math.floor(reaper.gmem_read(2))
  s.tc_f = math.floor(reaper.gmem_read(3))
  s.framerate_type = math.floor(reaper.gmem_read(4))
  s.tc_valid = reaper.gmem_read(6) > 0.5
  s.active_source = math.floor(reaper.gmem_read(17))

  -- JSFX detection: TC_WRITE_COUNTER at gmem[7] increments every @block
  local wc = math.floor(reaper.gmem_read(7))
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

-- Get the current active TC values
function M.get_active_tc()
  local s = M.state
  return s.tc_h, s.tc_m, s.tc_s, s.tc_f, M.SRC_NAMES[s.active_source] or "None"
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

-- Config persistence
function M.load_settings()
  local function gets(k)
    local v = reaper.GetExtState(M.EXT_SECTION, k)
    return v ~= "" and v or nil
  end
  local s = M.state
  local loaded_ip = gets("dest_ip")
  s.dest_ip = (loaded_ip and M.is_valid_ipv4(loaded_ip)) and loaded_ip or s.dest_ip
  s.artnet_enabled  = gets("artnet_enabled") == "true"
  s.osc_enabled    = gets("osc_enabled") == "true"
  local loaded_osc_ip = gets("osc_ip")
  s.osc_ip         = (loaded_osc_ip and M.is_valid_ipv4(loaded_osc_ip)) and loaded_osc_ip or s.osc_ip
  s.osc_port       = tonumber(gets("osc_port")) or 9000
  s.osc_address    = gets("osc_address") or "/tc"
  s.tc_offset_h        = tonumber(gets("tc_offset_h")) or 0
  s.tc_offset_m        = tonumber(gets("tc_offset_m")) or 0
  s.tc_offset_s        = tonumber(gets("tc_offset_s")) or 0
  s.tc_offset_f        = tonumber(gets("tc_offset_f")) or 0
  s.tc_offset_negative = gets("tc_offset_negative") == "true"

  -- Clean up legacy settings (framerate now owned by JSFX, old track-management keys)
  reaper.DeleteExtState(M.EXT_SECTION, "framerate_type", true)
  reaper.DeleteExtState(M.EXT_SECTION, "ltc_enabled", true)
  reaper.DeleteExtState(M.EXT_SECTION, "ltc_track_guid", true)
  reaper.DeleteExtState(M.EXT_SECTION, "ltc_fallback", true)
  reaper.DeleteExtState(M.EXT_SECTION, "threshold_db", true)
  reaper.DeleteExtState(M.EXT_SECTION, "mtc_enabled", true)
  reaper.DeleteExtState(M.EXT_SECTION, "mtc_track_guid", true)
end

function M.save_settings()
  local s = M.state
  local function sets(k, v) reaper.SetExtState(M.EXT_SECTION, k, tostring(v), true) end
  sets("dest_ip",        s.dest_ip)
  sets("artnet_enabled",  s.artnet_enabled)
  sets("osc_enabled",    s.osc_enabled)
  sets("osc_ip",         s.osc_ip)
  sets("osc_port",       s.osc_port)
  sets("osc_address",        s.osc_address)
  sets("tc_offset_h",        s.tc_offset_h)
  sets("tc_offset_m",        s.tc_offset_m)
  sets("tc_offset_s",        s.tc_offset_s)
  sets("tc_offset_f",        s.tc_offset_f)
  sets("tc_offset_negative", s.tc_offset_negative)
end

return M
