-- ReaTC core: constants, state, config, and timecode helpers

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

M.py_artnet  = M.script_path .. "reatc_udp.py"
M.py_mtc     = M.script_path .. "reatc_mtc.py"
M.py_ltcout  = M.script_path .. "reatc_ltcout.py"

M.is_win = reaper.GetOS():find("Win") ~= nil
M.dev_null = M.is_win and "2>NUL" or "2>/dev/null"

-- State
M.state = {
  -- Python
  python_bin   = nil,
  python_error = nil,

  -- Art-Net
  artnet_enabled   = false,
  dest_ip          = "2.0.0.1",
  framerate_type   = M.FR_EBU,
  packets_sent     = 0,
  artnet_error     = nil,
  last_artnet_time = 0,

  -- MTC
  mtc_enabled  = false,
  mtc_port     = "",         -- "" = virtual port
  mtc_proc     = nil,
  mtc_error    = nil,
  mtc_ports    = nil,        -- list of {name, index}
  last_mtc_time = 0,

  -- LTC audio output
  ltc_out_enabled  = false,
  ltc_out_device   = "",     -- "" = default device
  ltc_out_proc     = nil,
  ltc_out_error    = nil,
  ltc_out_devices  = nil,    -- list of {name, index}
  last_ltc_out_time = 0,

  -- LTC decoder configuration
  ltc_enabled    = false,
  ltc_track_idx  = nil,      -- 0-based track index or nil
  ltc_track      = nil,      -- MediaTrack handle
  threshold_db   = -24,
  ltc_fallback   = true,     -- auto-fallback to timeline when not locked

  -- UI state
  show_settings  = false,
  last_win_w     = M.MIN_WIN_W,
  last_win_h     = M.MIN_WIN_H,

  -- Audio accessor
  accessor       = nil,
  last_read_pos  = 0,

  -- Signal level monitoring
  peak_level     = 0,
  trans_count    = 0,  -- count of transitions detected

  -- Biphase mark decoder state (ported from LTC_Decoder.jsfx @sample)
  sig_state          = 0,   -- 0=deadband, 1=positive, -1=negative
  bpm_state          = 0,   -- 0=at boundary, 1=mid-bit of a '1' seen
  samples_since_trans = 0,
  bit_buf            = {},  -- circular buffer [1..512]
  bit_idx            = 0,   -- total bits pushed (use & 511 for index)
  last_gap           = 0,

  -- Decoded LTC timecode
  tc_h = 0, tc_m = 0, tc_s = 0, tc_f = 0, tc_type = M.FR_EBU,
  tc_valid          = false,
  last_valid_time   = 0,
  sync_count        = 0,
  last_sync_word    = 0,  -- for debugging
  bit_ones          = 0,  -- count of '1' bits for debugging
  bit_zeros         = 0,  -- count of '0' bits for debugging

  -- Transport timecode (used when LTC not active)
  tr_h = 0, tr_m = 0, tr_s = 0, tr_f = 0,

  -- Playback tracking (for accessor lifecycle)
  was_playing = false,

  -- LTC Generator
  editing_region_offset = nil,
  region_offset_text = nil,
}

-- Initialise bit buffer
for i = 1, 512 do M.state.bit_buf[i] = 0 end

-- Sample rate we request from the audio accessor
M.DECODER_SRATE = 44100

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

-- python-rtmidi install helper
function M.check_rtmidi()
  if not M.state.python_bin then return false end
  local q = M.is_win and ('"' .. M.state.python_bin .. '"') or M.state.python_bin
  local h = io.popen(q .. ' -c "import rtmidi; print(1)" 2>&1')
  if not h then return false end
  local r = h:read("*l"); h:close()
  return r == "1"
end

function M.try_install_rtmidi()
  local ret = reaper.ShowMessageBox(
    "python-rtmidi is required for MTC output.\n\n" ..
    "It is free and open-source (MIT license).\n" ..
    "Install it now? (requires internet connection)\n\n" ..
    "Command: pip3 install python-rtmidi",
    "Install dependency?", 4)  -- 4 = Yes/No buttons
  if ret ~= 6 then return false end  -- 6 = Yes
  local q = M.is_win and ('"' .. M.state.python_bin .. '"') or M.state.python_bin
  os.execute(q .. ' -m pip install python-rtmidi')
  if M.check_rtmidi() then return true end
  reaper.MB("Installation failed.\nPlease run: pip3 install python-rtmidi",
            "Install Failed", 0)
  return false
end

-- sounddevice install helper
function M.check_sounddevice()
  if not M.state.python_bin then return false end
  local q = M.is_win and ('"' .. M.state.python_bin .. '"') or M.state.python_bin
  local h = io.popen(q .. ' -c "import sounddevice; import numpy; print(1)" 2>&1')
  if not h then return false end
  local r = h:read("*l"); h:close()
  return r == "1"
end

function M.try_install_sounddevice()
  local ret = reaper.ShowMessageBox(
    "sounddevice and numpy are required for LTC audio output.\n\n" ..
    "Both are free and open-source.\n" ..
    "Install them now? (requires internet connection)\n\n" ..
    "Command: pip3 install sounddevice numpy",
    "Install dependency?", 4)  -- 4 = Yes/No buttons
  if ret ~= 6 then return false end  -- 6 = Yes
  local q = M.is_win and ('"' .. M.state.python_bin .. '"') or M.state.python_bin
  os.execute(q .. ' -m pip install sounddevice numpy')
  if M.check_sounddevice() then return true end
  reaper.MB("Installation failed.\nPlease run: pip3 install sounddevice numpy",
            "Install Failed", 0)
  return false
end

-- Audio output device listing
function M.list_audio_devices()
  if not M.state.python_bin then return {} end
  local q   = M.is_win and ('"' .. M.state.python_bin .. '"') or M.state.python_bin
  local cmd = q .. ' "' .. M.py_ltcout .. '" --list-devices 2>&1'
  local h   = io.popen(cmd)
  if not h then return {} end
  local out = h:read("*a"); h:close()
  local devices = { { name = "Default Device", index = -1 } }
  for line in out:gmatch("[^\n]+") do
    local idx, name = line:match("^(%d+): (.+)")
    if idx then table.insert(devices, { name = name, index = tonumber(idx) }) end
  end
  return devices
end


-- MIDI port listing
function M.list_midi_ports()
  if not M.state.python_bin then return {} end
  local q   = M.is_win and ('"' .. M.state.python_bin .. '"') or M.state.python_bin
  local cmd = q .. ' "' .. M.py_mtc .. '" --list-ports 2>&1'
  local h   = io.popen(cmd)
  if not h then return {} end
  local out = h:read("*a"); h:close()
  local ports = { { name = "Virtual Port (REAPER MTC Out)", index = -1 } }
  for line in out:gmatch("[^\n]+") do
    local idx, name = line:match("^(%d+): (.+)")
    if idx then table.insert(ports, { name = name, index = tonumber(idx) }) end
  end
  return ports
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

function M.seconds_to_timecode(pos, fr_type)
  local fps = M.FPS_VAL[fr_type + 1]
  if fps == 29.97 then
    local total = math.floor(pos * 30)
    local d  = math.floor(total / 17982)
    local mm = total % 17982
    local tf = total + 18 * d + 2 * math.floor((mm - 2) / 1798)
    return math.floor(tf / 108000) % 24,
           math.floor(tf / 1800) % 60,
           math.floor(tf / 30) % 60,
           tf % 30
  else
    local int_fps = M.FPS_INT[fr_type + 1]
    local total   = math.floor(pos * fps)
    local frames  = total % int_fps
    local ts      = math.floor(total / fps)
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
  s.dest_ip        = gets("dest_ip")        or s.dest_ip
  s.framerate_type = tonumber(gets("framerate_type")) or s.framerate_type
  s.artnet_enabled = gets("artnet_enabled") == "true"
  s.mtc_enabled    = gets("mtc_enabled")    == "true"
  s.mtc_port       = gets("mtc_port")       or ""
  s.ltc_enabled    = gets("ltc_enabled")    == "true"
  s.ltc_track_idx  = tonumber(gets("ltc_track_idx"))
  s.threshold_db   = tonumber(gets("threshold_db")) or -24
  s.ltc_fallback   = gets("ltc_fallback") ~= "false"  -- default true
  s.ltc_out_enabled = gets("ltc_out_enabled") == "true"
  s.ltc_out_device  = gets("ltc_out_device")  or ""
end

function M.save_settings()
  local s = M.state
  local function sets(k, v) reaper.SetExtState(M.EXT_SECTION, k, tostring(v), true) end
  sets("dest_ip",        s.dest_ip)
  sets("framerate_type", s.framerate_type)
  sets("artnet_enabled", s.artnet_enabled)
  sets("mtc_enabled",    s.mtc_enabled)
  sets("mtc_port",       s.mtc_port)
  sets("ltc_enabled",    s.ltc_enabled)
  sets("ltc_track_idx",  s.ltc_track_idx or "")
  sets("threshold_db",   s.threshold_db)
  sets("ltc_fallback",   s.ltc_fallback)
  sets("ltc_out_enabled", s.ltc_out_enabled)
  sets("ltc_out_device",  s.ltc_out_device)
end

return M
