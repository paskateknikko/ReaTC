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
 */

#include "reaper_plugin.h"
#include <cstring>
#include <string>

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

// Script filenames (relative to <ResourcePath>/Scripts/ReaTC/Timecode/)
static const char* g_script_files[2] = {
  "reatc.lua",
  "reatc_regions_to_ltc.lua",
};

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
    std::string path = GetResourcePath();
#ifdef _WIN32
    path += "\\Scripts\\ReaTC\\Timecode\\";
#else
    path += "/Scripts/ReaTC/Timecode/";
#endif
    path += g_script_files[index];
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
    // Clean up cached script registrations
    if (AddRemoveReaScript && GetResourcePath) {
      for (int i = 0; i < 2; ++i) {
        if (g_script_ids[i] > 0) {
          std::string path = GetResourcePath();
#ifdef _WIN32
          path += "\\Scripts\\ReaTC\\Timecode\\";
#else
          path += "/Scripts/ReaTC/Timecode/";
#endif
          path += g_script_files[i];
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

  plugin_register = rec->Register;

  // Register custom actions
  for (int i = 0; i < ACT_COUNT; ++i) {
    g_cmd_ids[i] = rec->Register("custom_action", &g_actions[i]);
    if (g_cmd_ids[i] == 0) {
      log_msg("ReaTC: failed to register custom action\n");
      return 0;
    }
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

  // Log successful load with assigned command IDs
  {
    std::string msg = "ReaTC extension loaded — action IDs:";
    for (int i = 0; i < ACT_COUNT; ++i)
      msg += " " + std::to_string(g_cmd_ids[i]);
    msg += "\n";
    log_msg(msg.c_str());
  }

  return 1; // success
}
