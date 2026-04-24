--- ReaTC — https://github.com/paskateknikko/ReaTC
-- Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
--
--- ReaTC core module: constants, shared state, config persistence, and timecode math.
-- All other modules depend on this. The `state` table is shared across the entire
-- ReaTC runtime — UI, outputs, and the main loop all read/write it.
-- @module reatc_core
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

M.py_artnet       = M.script_path .. "reatc_artnet.py"
M.py_osc          = M.script_path .. "reatc_osc.py"
M.py_netdiscover  = M.script_path .. "reatc_netdiscover.py"

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
  artnet_enabled        = false,
  artnet_proc           = nil,
  dest_ip               = "2.0.0.1",
  artnet_preferred_ip   = "",  -- CIDR (e.g. "10.0.0.0/8") or "" = auto
  artnet_preferred_iface = "",  -- explicit NIC name override, "" = none
  framerate_type        = M.FR_EBU,
  packets_sent          = 0,
  artnet_error          = nil,
  last_artnet_time      = 0,

  -- OSC
  osc_enabled          = false,
  osc_ip               = "127.0.0.1",
  osc_port             = 9000,
  osc_address          = "/tc",
  osc_preferred_ip     = "",
  osc_preferred_iface  = "",
  osc_proc             = nil,
  osc_error            = nil,
  last_osc_time        = 0,
  osc_packets_sent     = 0,

  -- Network interface discovery (populated lazily by list_interfaces())
  interfaces       = nil,  -- array of { ip, iface, broadcast, netmask }

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

--- Validate a comma-separated list of IPv4 addresses (for multi-unicast).
-- Whitespace around commas is allowed. An empty list is invalid.
-- @param list string e.g. "192.168.0.50, 192.168.0.51"
-- @return boolean true if every item is a valid IPv4
function M.is_valid_ipv4_list(list)
  if not list or type(list) ~= "string" then return false end
  local count = 0
  for item in list:gmatch("[^,]+") do
    local trimmed = item:gsub("^%s+", ""):gsub("%s+$", "")
    if not M.is_valid_ipv4(trimmed) then return false end
    count = count + 1
  end
  return count > 0
end

--- List local IPv4 interfaces by invoking reatc_netdiscover.py.
-- Output is tab-separated (iface names can contain spaces: "Wi-Fi 2").
-- Caches the result in `state.interfaces`. Pass `force = true` to refresh.
-- @param force boolean re-run discovery even if cached
-- @return table array of { ip, iface, broadcast, netmask } (possibly empty)
function M.list_interfaces(force)
  local s = M.state
  if s.interfaces and not force then return s.interfaces end
  s.interfaces = {}
  if not s.python_bin then return s.interfaces end

  local q = M.is_win and ('"' .. s.python_bin .. '"') or s.python_bin
  local cmd = q .. ' "' .. M.py_netdiscover .. '" ' .. M.dev_null
  local h = io.popen(cmd, "r")
  if not h then return s.interfaces end
  local out = h:read("*a") or ""
  h:close()

  for line in out:gmatch("[^\r\n]+") do
    local ip, iface, bcast, mask = line:match("^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)$")
    if ip and M.is_valid_ipv4(ip) then
      s.interfaces[#s.interfaces + 1] = {
        ip = ip,
        iface = iface,
        broadcast = (bcast ~= "-") and bcast or nil,
        netmask = mask,
      }
    end
  end
  return s.interfaces
end

--- Convert a dotted-quad IPv4 to a 32-bit integer, or nil on invalid input.
local function ipv4_to_int(ip)
  if not M.is_valid_ipv4(ip) then return nil end
  local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  return ((tonumber(a) << 24) | (tonumber(b) << 16)
        | (tonumber(c) << 8)  | tonumber(d)) & 0xFFFFFFFF
end

--- Validate a CIDR notation string or bare IPv4 (treated as /32).
-- @param s string e.g. "10.0.0.0/8" or "192.168.1.100"
-- @return boolean true if the input parses as a valid IPv4 network
function M.is_valid_cidr(s)
  if not s or type(s) ~= "string" or s == "" then return false end
  local net, prefix_str = s:match("^([%d.]+)/(%d+)$")
  if not net then
    return M.is_valid_ipv4(s)
  end
  local prefix = tonumber(prefix_str)
  if not prefix or prefix < 0 or prefix > 32 then return false end
  return M.is_valid_ipv4(net)
end

--- Test whether an IPv4 falls inside a CIDR range.
-- A bare IP (no /prefix) is treated as /32 — only an exact match succeeds.
-- @param ip string dotted-quad IPv4
-- @param cidr string "network/prefix" or bare IPv4
-- @return boolean true if ip is in the CIDR range
function M.cidr_match(ip, cidr)
  if not (ip and cidr) then return false end
  local net, prefix_str = cidr:match("^([%d.]+)/(%d+)$")
  local prefix
  if net then
    prefix = tonumber(prefix_str)
  else
    net = cidr
    prefix = 32
  end
  if not (prefix and prefix >= 0 and prefix <= 32) then return false end
  local net_int = ipv4_to_int(net)
  local ip_int  = ipv4_to_int(ip)
  if not (net_int and ip_int) then return false end
  if prefix == 0 then return true end
  local mask = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF
  return (net_int & mask) == (ip_int & mask)
end

--- Resolve a preferred-IP / preferred-interface pair to a concrete bind IP.
-- Resolution order: explicit interface override → CIDR match → none (Auto).
-- @param preferred_ip string CIDR or IP (or "" for none)
-- @param preferred_iface string interface name (or "" for none)
-- @return string|nil resolved IPv4 to bind to, or nil for Auto/default route
-- @return string|nil human-readable "iface (ip)" label, or nil for Auto
function M.resolve_bind_ip(preferred_ip, preferred_iface)
  local ifaces = M.list_interfaces()

  if preferred_iface and preferred_iface ~= "" then
    for _, it in ipairs(ifaces) do
      if it.iface == preferred_iface then
        return it.ip, string.format("%s (%s)", it.iface, it.ip)
      end
    end
  end

  if preferred_ip and preferred_ip ~= "" then
    for _, it in ipairs(ifaces) do
      if M.cidr_match(it.ip, preferred_ip) then
        return it.ip, string.format("%s (%s)", it.iface, it.ip)
      end
    end
  end

  return nil, nil
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
  DEST_IP                = "dest_ip",
  ARTNET_ENABLED         = "artnet_enabled",
  ARTNET_PREFERRED_IP    = "artnet_preferred_ip",
  ARTNET_PREFERRED_IFACE = "artnet_preferred_iface",
  OSC_ENABLED            = "osc_enabled",
  OSC_IP                 = "osc_ip",
  OSC_PORT               = "osc_port",
  OSC_ADDRESS            = "osc_address",
  OSC_PREFERRED_IP       = "osc_preferred_ip",
  OSC_PREFERRED_IFACE    = "osc_preferred_iface",
  TC_OFFSET_H            = "tc_offset_h",
  TC_OFFSET_M            = "tc_offset_m",
  TC_OFFSET_S            = "tc_offset_s",
  TC_OFFSET_F            = "tc_offset_f",
  TC_OFFSET_NEGATIVE     = "tc_offset_negative",
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
  s.dest_ip = (loaded_ip and M.is_valid_ipv4_list(loaded_ip)) and loaded_ip or s.dest_ip
  s.artnet_enabled  = gets(SK.ARTNET_ENABLED) == "true"
  local loaded_artnet_cidr = gets(SK.ARTNET_PREFERRED_IP)
  s.artnet_preferred_ip    = (loaded_artnet_cidr and M.is_valid_cidr(loaded_artnet_cidr))
                             and loaded_artnet_cidr or ""
  s.artnet_preferred_iface = gets(SK.ARTNET_PREFERRED_IFACE) or ""
  s.osc_enabled    = gets(SK.OSC_ENABLED) == "true"
  local loaded_osc_ip = gets(SK.OSC_IP)
  s.osc_ip         = (loaded_osc_ip and M.is_valid_ipv4(loaded_osc_ip)) and loaded_osc_ip or s.osc_ip
  s.osc_port       = tonumber(gets(SK.OSC_PORT)) or 9000
  s.osc_address    = gets(SK.OSC_ADDRESS) or "/tc"
  local loaded_osc_cidr = gets(SK.OSC_PREFERRED_IP)
  s.osc_preferred_ip     = (loaded_osc_cidr and M.is_valid_cidr(loaded_osc_cidr))
                           and loaded_osc_cidr or ""
  s.osc_preferred_iface  = gets(SK.OSC_PREFERRED_IFACE) or ""
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
  sets(SK.DEST_IP,                s.dest_ip)
  sets(SK.ARTNET_ENABLED,         s.artnet_enabled)
  sets(SK.ARTNET_PREFERRED_IP,    s.artnet_preferred_ip)
  sets(SK.ARTNET_PREFERRED_IFACE, s.artnet_preferred_iface)
  sets(SK.OSC_ENABLED,            s.osc_enabled)
  sets(SK.OSC_IP,                 s.osc_ip)
  sets(SK.OSC_PORT,               s.osc_port)
  sets(SK.OSC_ADDRESS,            s.osc_address)
  sets(SK.OSC_PREFERRED_IP,       s.osc_preferred_ip)
  sets(SK.OSC_PREFERRED_IFACE,    s.osc_preferred_iface)
  sets(SK.TC_OFFSET_H,       s.tc_offset_h)
  sets(SK.TC_OFFSET_M,       s.tc_offset_m)
  sets(SK.TC_OFFSET_S,       s.tc_offset_s)
  sets(SK.TC_OFFSET_F,       s.tc_offset_f)
  sets(SK.TC_OFFSET_NEGATIVE, s.tc_offset_negative)
end

return M
