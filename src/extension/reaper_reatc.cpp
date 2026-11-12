/*
 * reaper_reatc.cpp — REAPER extension for ReaTC custom command IDs
 *
 * Registers human-readable action names so ReaTC can be controlled via OSC,
 * MIDI controllers, or any REAPER action trigger:
 *
 *   _REATC_MAIN           Launch/toggle ReaTC UI
 *   _REATC_BAKE_LTC       Run Regions-to-LTC script
 *   _REATC_TOGGLE_ARTNET  Toggle Art-Net output
 *   _REATC_TOGGLE_OSC     Toggle OSC output
 *
 * and exports a small ReaScript API used by reatc.lua for network output
 * (no Python, no subprocesses):
 *
 *   ReaTC_GetVersion()       extension version string
 *   ReaTC_ListInterfaces()   local IPv4 interfaces (tab-separated rows)
 *   ReaTC_SendArtNetTC(...)  send one Art-Net TimeCode packet
 *   ReaTC_SendOSCTC(...)     send one OSC timecode message
 *   ReaTC_GetLastError(kind) last error/warning for "artnet" or "osc"
 *
 * Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
 */

/**
 * @file reaper_reatc.cpp
 * @brief REAPER extension that registers ReaTC custom actions and brokers
 *        IPC between the action system and the Lua scripts via ExtState.
 *
 * ExtState IPC contract
 * ---------------------
 * **ReaTC_CMD** (extension -> script, consumed once by Lua):
 *   - "toggle_artnet" = "1"   Request the Lua script to toggle Art-Net output.
 *   - "toggle_osc"    = "1"   Request the Lua script to toggle OSC output.
 *
 * **ReaTC_STATE** (script -> extension, read-only by C++):
 *   - "artnet"  = "0"|"1"    Current Art-Net output state (for toggle_action).
 *   - "osc"     = "0"|"1"    Current OSC output state (for toggle_action).
 *
 * **JSFX slider polling** (JSFX -> extension, via TrackFX_GetParam):
 *   - slider25 (_open_script_cmd): set to 1 by JSFX "Open Script" button,
 *     polled by timer, reset to 0 after launching the script.
 */

#include "reaper_plugin.h"
#include <cstdint>
#include <cstring>
#include <string>

#include "reatc_net.h"
#include "reatc_packets.h"

#ifndef REATC_VERSION
#define REATC_VERSION "DEV"
#endif

// ---------------------------------------------------------------------------
// REAPER API function pointers (resolved at load time via GetFunc)
// ---------------------------------------------------------------------------
static void     (*Main_OnCommand)(int command, int flag);
static const char* (*GetResourcePath)();
static int      (*AddRemoveReaScript)(bool add, int sectionID, const char* scriptfn, bool commit);
static void     (*SetExtState)(const char* section, const char* key, const char* value, bool persist);
static const char* (*GetExtState)(const char* section, const char* key);
static void     (*DeleteExtState)(const char* section, const char* key, bool persist);
static int      (*plugin_register)(const char* name, void* infostruct);
static void     (*ShowConsoleMsg)(const char* msg); // optional — for diagnostics

// TrackFX API — for polling JSFX "Open Script" slider
static int         (*CountTracks)(ReaProject* proj);
static MediaTrack* (*GetTrack)(ReaProject* proj, int trackidx);
static MediaTrack* (*GetMasterTrack)(ReaProject* proj);
static int         (*TrackFX_GetCount)(MediaTrack* track);
static bool        (*TrackFX_GetFXName)(MediaTrack* track, int fx, char* buf, int buf_sz);
static double      (*TrackFX_GetParam)(MediaTrack* track, int fx, int param, double* minvalOut, double* maxvalOut);
static bool        (*TrackFX_SetParam)(MediaTrack* track, int fx, int param, double val);

// ---------------------------------------------------------------------------
// Action definitions
// ---------------------------------------------------------------------------
enum ActionIndex { ACT_MAIN, ACT_BAKE, ACT_ARTNET, ACT_OSC, ACT_COUNT };

static custom_action_register_t g_actions[ACT_COUNT] = {
  { 0, "_REATC_MAIN",           "ReaTC: Launch/toggle UI",       nullptr },
  { 0, "_REATC_BAKE_LTC",       "ReaTC: Regions to LTC",         nullptr },
  { 0, "_REATC_TOGGLE_ARTNET",  "ReaTC: Toggle Art-Net output",  nullptr },
  { 0, "_REATC_TOGGLE_OSC",     "ReaTC: Toggle OSC output",      nullptr },
};

static int g_cmd_ids[ACT_COUNT] = {};   // filled by Register("custom_action")
static int g_script_ids[2] = { 0, 0 };  // cached command IDs for the two Lua scripts

// Script filenames (basename only — resolved against multiple search paths)
static const char* g_script_files[2] = {
  "reatc.lua",
  "reatc_regions_to_ltc.lua",
};

// Script path relative to REAPER resource dir
// Matches ReaPack install: <type>/<index_name>/<category>/
static const char* SCRIPT_DIR =
#ifdef _WIN32
  "\\Scripts\\ReaTC\\Timecode\\";
#else
  "/Scripts/ReaTC/Timecode/";
#endif

// ---------------------------------------------------------------------------
// Logging helper (no-op if ShowConsoleMsg unavailable)
// ---------------------------------------------------------------------------
static void log_msg(const char* msg)
{
  if (ShowConsoleMsg) ShowConsoleMsg(msg);
}

// ---------------------------------------------------------------------------
// Script resolution: find and run a Lua script via AddRemoveReaScript
// ---------------------------------------------------------------------------
/**
 * @brief Resolve a Lua script path and execute it via Main_OnCommand.
 * @param index  0 = reatc.lua (main UI), 1 = reatc_regions_to_ltc.lua
 *
 * The command ID is cached after the first call so that AddRemoveReaScript
 * is only invoked once per script per session.
 */
static void run_script(int index)
{
  if (!GetResourcePath || !AddRemoveReaScript || !Main_OnCommand) return;

  // Resolve script command ID on first use
  if (g_script_ids[index] == 0) {
    std::string path = std::string(GetResourcePath()) + SCRIPT_DIR +
                       g_script_files[index];
    g_script_ids[index] = AddRemoveReaScript(true, 0, path.c_str(), false);

    if (g_script_ids[index] == 0) {
      std::string err = "ReaTC: script not found: " + path + "\n";
      log_msg(err.c_str());
      return;
    }
  }

  if (g_script_ids[index] > 0)
    Main_OnCommand(g_script_ids[index], 0);
}

// ---------------------------------------------------------------------------
// JSFX slider polling — detect "Open Script" button clicks from JSFX GUI
// ---------------------------------------------------------------------------

// Parameter index of slider25 in the JSFX (0-based, sequential declaration order).
// slider1..slider23 = params 0..19, slider25 = param 20.
static const int JSFX_PARAM_OPEN_SCRIPT = 20;

static int g_poll_counter = 0;

/**
 * @brief Check if a given track/FX slot is the ReaTC JSFX.
 * @return true if the FX name contains "ReaTC Timecode Converter".
 */
static bool is_reatc_jsfx(MediaTrack* track, int fx)
{
  char name[256];
  if (!TrackFX_GetFXName(track, fx, name, sizeof(name))) return false;
  return strstr(name, "ReaTC Timecode Converter") != nullptr;
}

/**
 * @brief Check slider25 on a single track/FX and launch script if set.
 * @return true if a flag was found and consumed.
 */
static bool check_open_flag(MediaTrack* track, int fx)
{
  double minval, maxval;
  double val = TrackFX_GetParam(track, fx, JSFX_PARAM_OPEN_SCRIPT,
                                &minval, &maxval);
  if (val > 0.5) {
    TrackFX_SetParam(track, fx, JSFX_PARAM_OPEN_SCRIPT, 0.0);
    run_script(0);
    return true;
  }
  return false;
}

/**
 * @brief Timer callback (~30Hz). Polls all ReaTC JSFX instances every
 *        ~200ms (6 ticks). When any instance's open-script flag is set,
 *        resets it and launches the main Lua script.
 */
static void poll_jsfx_open_request()
{
  // Throttle: only poll every 6th tick (~200ms at 30Hz)
  if (++g_poll_counter < 6) return;
  g_poll_counter = 0;

  // Check master track
  MediaTrack* master = GetMasterTrack(nullptr);
  if (master) {
    int count = TrackFX_GetCount(master);
    for (int i = 0; i < count; ++i) {
      if (is_reatc_jsfx(master, i) && check_open_flag(master, i)) return;
    }
  }

  // Check all regular tracks
  int num_tracks = CountTracks(nullptr);
  for (int t = 0; t < num_tracks; ++t) {
    MediaTrack* track = GetTrack(nullptr, t);
    if (!track) continue;
    int count = TrackFX_GetCount(track);
    for (int i = 0; i < count; ++i) {
      if (is_reatc_jsfx(track, i) && check_open_flag(track, i)) return;
    }
  }
}

// ---------------------------------------------------------------------------
// hookcommand2 — intercept our custom action triggers
// ---------------------------------------------------------------------------
/**
 * @brief REAPER hookcommand2 callback — intercept our registered action IDs.
 *
 * ACT_MAIN and ACT_BAKE launch Lua scripts directly.  ACT_ARTNET and
 * ACT_OSC write a one-shot flag into ReaTC_CMD ExtState, which the
 * running Lua script polls and consumes on its next defer cycle.
 *
 * @return true if the command was handled, false to let REAPER continue.
 */
static bool hook_command2(KbdSectionInfo* sec, int command, int val, int val2, int relmode, HWND hwnd)
{
  if (command == g_cmd_ids[ACT_MAIN]) {
    run_script(0);
    return true;
  }
  if (command == g_cmd_ids[ACT_BAKE]) {
    run_script(1);
    return true;
  }
  if (command == g_cmd_ids[ACT_ARTNET]) {
    SetExtState("ReaTC_CMD", "toggle_artnet", "1", false);
    return true;
  }
  if (command == g_cmd_ids[ACT_OSC]) {
    SetExtState("ReaTC_CMD", "toggle_osc", "1", false);
    return true;
  }
  return false; // not our action
}

// ---------------------------------------------------------------------------
// toggleaction — report on/off state for toggle actions in Actions list
// ---------------------------------------------------------------------------
/**
 * @brief REAPER toggleaction callback — report on/off state for the Actions list.
 *
 * Reads ReaTC_STATE ExtState keys written by the Lua script to reflect
 * the current toggle state of Art-Net and OSC outputs.
 *
 * @return 1 = on, 0 = off, -1 = not our action.
 */
static int toggle_action(int command_id)
{
  if (!GetExtState) return -1;

  if (command_id == g_cmd_ids[ACT_ARTNET]) {
    const char* v = GetExtState("ReaTC_STATE", "artnet");
    return (v && v[0] == '1') ? 1 : 0;
  }
  if (command_id == g_cmd_ids[ACT_OSC]) {
    const char* v = GetExtState("ReaTC_STATE", "osc");
    return (v && v[0] == '1') ? 1 : 0;
  }
  return -1; // not our action
}

// ---------------------------------------------------------------------------
// ReaScript API: network output
// ---------------------------------------------------------------------------
// All functions run on REAPER's main thread (called from the Lua defer loop),
// so no locking is needed. Sockets live for the session and are rebuilt when
// the source IP changes.

static reatc::UdpSender g_artnet;
static reatc::UdpSender g_osc;
static std::string g_ifaces_buf;  // backing store for ReaTC_ListInterfaces
static std::string g_err_buf;     // backing store for ReaTC_GetLastError

static const char* ReaTC_GetVersion() { return REATC_VERSION; }

static const char* ReaTC_ListInterfaces()
{
  g_ifaces_buf = reatc::list_interfaces();
  return g_ifaces_buf.c_str();
}

static int ReaTC_SendArtNetTC(const char* dests, const char* srcIP, int streamID,
                              int h, int m, int s, int f, int type)
{
  if (!reatc::tc_in_range(h, m, s, f, type)) return -1;
  uint8_t pkt[reatc::ARTNET_TC_LEN];
  reatc::build_artnet_timecode(pkt, h, m, s, f, type, streamID);
  return g_artnet.send(dests ? dests : "", reatc::ARTNET_PORT,
                       srcIP ? srcIP : "", pkt, sizeof(pkt));
}

static int ReaTC_SendOSCTC(const char* destIP, int port, const char* address,
                           const char* srcIP, int h, int m, int s, int f, int type)
{
  if (!reatc::tc_in_range(h, m, s, f, type)) return -1;
  if (!address || address[0] != '/') return -1;
  const auto pkt = reatc::build_osc_timecode(address, h, m, s, f, type);
  return g_osc.send(destIP ? destIP : "", port, srcIP ? srcIP : "",
                    pkt.data(), pkt.size());
}

static const char* ReaTC_GetLastError(const char* kind)
{
  if (kind && std::strcmp(kind, "osc") == 0) g_err_buf = g_osc.last_error();
  else g_err_buf = g_artnet.last_error();
  return g_err_buf.c_str();
}

// vararg wrappers: ReaScript passes ints as intptr_t-sized values in arglist.
#define ARG_I(i) static_cast<int>(reinterpret_cast<intptr_t>(arglist[i]))
#define ARG_S(i) static_cast<const char*>(arglist[i])

static void* va_GetVersion(void**, int)
{
  return (void*)ReaTC_GetVersion();
}
static void* va_ListInterfaces(void**, int)
{
  return (void*)ReaTC_ListInterfaces();
}
static void* va_SendArtNetTC(void** arglist, int n)
{
  if (n < 8) return (void*)(intptr_t)-1;
  return (void*)(intptr_t)ReaTC_SendArtNetTC(ARG_S(0), ARG_S(1), ARG_I(2),
      ARG_I(3), ARG_I(4), ARG_I(5), ARG_I(6), ARG_I(7));
}
static void* va_SendOSCTC(void** arglist, int n)
{
  if (n < 9) return (void*)(intptr_t)-1;
  return (void*)(intptr_t)ReaTC_SendOSCTC(ARG_S(0), ARG_I(1), ARG_S(2), ARG_S(3),
      ARG_I(4), ARG_I(5), ARG_I(6), ARG_I(7), ARG_I(8));
}
static void* va_GetLastError(void** arglist, int n)
{
  return (void*)ReaTC_GetLastError(n > 0 ? ARG_S(0) : nullptr);
}

#undef ARG_I
#undef ARG_S

struct ApiFunc {
  const char* name;  // without the API_ prefix
  void* func;
  void* vararg;
  const char* def;   // "ret\0argtypes\0argnames\0help"
};

static const ApiFunc g_api[] = {
  { "ReaTC_GetVersion", (void*)ReaTC_GetVersion, (void*)va_GetVersion,
    "const char*\0\0\0ReaTC extension version string." },
  { "ReaTC_ListInterfaces", (void*)ReaTC_ListInterfaces, (void*)va_ListInterfaces,
    "const char*\0\0\0Local up, non-loopback IPv4 interfaces, one per line: "
    "ip<TAB>name<TAB>broadcast-or-dash<TAB>netmask." },
  { "ReaTC_SendArtNetTC", (void*)ReaTC_SendArtNetTC, (void*)va_SendArtNetTC,
    "int\0const char*,const char*,int,int,int,int,int,int\0"
    "dests,srcIP,streamID,hours,minutes,seconds,frames,type\0"
    "Send one Art-Net TimeCode packet to each comma-separated destination. "
    "srcIP binds the socket to a local IPv4 (empty = default route). "
    "type: 0=24, 1=25, 2=29.97DF, 3=30. Returns packets sent, or -1 on error "
    "(see ReaTC_GetLastError(\"artnet\"))." },
  { "ReaTC_SendOSCTC", (void*)ReaTC_SendOSCTC, (void*)va_SendOSCTC,
    "int\0const char*,int,const char*,const char*,int,int,int,int,int\0"
    "destIP,port,address,srcIP,hours,minutes,seconds,frames,type\0"
    "Send one OSC message '<address> ,iiiii H M S F type'. Returns 1, or -1 on "
    "error (see ReaTC_GetLastError(\"osc\"))." },
  { "ReaTC_GetLastError", (void*)ReaTC_GetLastError, (void*)va_GetLastError,
    "const char*\0const char*\0kind\0"
    "Last error (after a failed send) or bind warning (after a successful send) "
    "for kind \"artnet\" or \"osc\"; empty if none." },
};

static void register_api(bool add)
{
  if (!plugin_register) return;
  for (const auto& a : g_api) {
    const std::string pre = add ? "" : "-";
    plugin_register((pre + "API_" + a.name).c_str(), a.func);
    plugin_register((pre + "APIdef_" + a.name).c_str(), (void*)a.def);
    plugin_register((pre + "APIvararg_" + a.name).c_str(), a.vararg);
  }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
/**
 * @brief Extension entry point called by REAPER on load and unload.
 *
 * On load (rec != NULL): resolves API function pointers, registers four
 * custom actions, and installs hookcommand2 + toggleaction callbacks.
 * On unload (rec == NULL): removes cached script registrations.
 *
 * @return 1 on success, 0 on failure or unload.
 */
extern "C" REAPER_PLUGIN_DLL_EXPORT int ReaperPluginEntry(
    HINSTANCE hInstance, reaper_plugin_info_t* rec)
{
  // rec == NULL means unload
  if (!rec) {
    // Unregister timer
    if (plugin_register)
      plugin_register("-timer", (void*)poll_jsfx_open_request);

    // Network output: unregister API, close sockets
    register_api(false);
    g_artnet.close();
    g_osc.close();
    reatc::net_shutdown();

    // Clean up cached script registrations
    if (AddRemoveReaScript && GetResourcePath) {
      for (int i = 0; i < 2; ++i) {
        if (g_script_ids[i] > 0) {
          std::string path = std::string(GetResourcePath()) + SCRIPT_DIR +
                             g_script_files[i];
          AddRemoveReaScript(false, 0, path.c_str(), false);
          g_script_ids[i] = 0;
        }
      }
    }
    return 0;
  }

  if (rec->caller_version != REAPER_PLUGIN_VERSION)
    return 0;

  // Resolve API functions
  #define LOAD_API(name) \
    *((void**)&name) = rec->GetFunc(#name); \
    if (!name) return 0;

  LOAD_API(Main_OnCommand);
  LOAD_API(GetResourcePath);
  LOAD_API(AddRemoveReaScript);
  LOAD_API(SetExtState);
  LOAD_API(GetExtState);
  LOAD_API(DeleteExtState);

  #undef LOAD_API

  // Optional API — used for diagnostics only
  *((void**)&ShowConsoleMsg) = rec->GetFunc("ShowConsoleMsg");

  // TrackFX API — optional, needed for JSFX "Open Script" button polling
  *((void**)&CountTracks)       = rec->GetFunc("CountTracks");
  *((void**)&GetTrack)          = rec->GetFunc("GetTrack");
  *((void**)&GetMasterTrack)    = rec->GetFunc("GetMasterTrack");
  *((void**)&TrackFX_GetCount)  = rec->GetFunc("TrackFX_GetCount");
  *((void**)&TrackFX_GetFXName) = rec->GetFunc("TrackFX_GetFXName");
  *((void**)&TrackFX_GetParam)  = rec->GetFunc("TrackFX_GetParam");
  *((void**)&TrackFX_SetParam)  = rec->GetFunc("TrackFX_SetParam");

  plugin_register = rec->Register;

  // Register custom actions (non-fatal on failure — a second copy of the
  // extension may already own these IDs, e.g. local + ReaPack install)
  int registered = 0;
  for (int i = 0; i < ACT_COUNT; ++i) {
    g_cmd_ids[i] = rec->Register("custom_action", &g_actions[i]);
    if (g_cmd_ids[i] == 0) {
      log_msg("ReaTC: skipping already-registered action (duplicate extension?)\n");
    } else {
      ++registered;
    }
  }
  if (registered == 0) {
    log_msg("ReaTC: no actions registered — another copy of the extension is loaded\n");
    return 0;
  }

  // Register callbacks
  if (!rec->Register("hookcommand2", (void*)hook_command2)) {
    log_msg("ReaTC: failed to register hookcommand2\n");
    return 0;
  }
  if (!rec->Register("toggleaction", (void*)toggle_action)) {
    log_msg("ReaTC: failed to register toggleaction\n");
    return 0;
  }

  // ReaScript API for network output (Art-Net / OSC / interface discovery)
  reatc::net_init();
  register_api(true);

  // Register JSFX slider polling timer (only if TrackFX API is available)
  if (CountTracks && GetTrack && GetMasterTrack &&
      TrackFX_GetCount && TrackFX_GetFXName &&
      TrackFX_GetParam && TrackFX_SetParam) {
    rec->Register("timer", (void*)poll_jsfx_open_request);
  }

  return 1; // success
}
