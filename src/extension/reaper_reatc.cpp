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

// Script filenames (relative to <ResourcePath>/Scripts/ReaTC/)
static const char* g_script_files[2] = {
  "reatc.lua",
  "reatc_regions_to_ltc.lua",
};

// ---------------------------------------------------------------------------
// Script resolution: find and run a Lua script via AddRemoveReaScript
// ---------------------------------------------------------------------------
static void run_script(int index)
{
  if (!GetResourcePath || !AddRemoveReaScript || !Main_OnCommand) return;

  // Resolve script command ID on first use
  if (g_script_ids[index] == 0) {
    std::string path = GetResourcePath();
#ifdef _WIN32
    path += "\\Scripts\\ReaTC\\";
#else
    path += "/Scripts/ReaTC/";
#endif
    path += g_script_files[index];
    g_script_ids[index] = AddRemoveReaScript(true, 0, path.c_str(), false);
  }

  if (g_script_ids[index] > 0)
    Main_OnCommand(g_script_ids[index], 0);
}

// ---------------------------------------------------------------------------
// hookcommand2 — intercept our custom action triggers
// ---------------------------------------------------------------------------
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
          path += "\\Scripts\\ReaTC\\";
#else
          path += "/Scripts/ReaTC/";
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

  plugin_register = rec->Register;

  // Register custom actions
  for (int i = 0; i < ACT_COUNT; ++i) {
    g_cmd_ids[i] = rec->Register("custom_action", &g_actions[i]);
    if (g_cmd_ids[i] == 0) return 0; // registration failed
  }

  // Register callbacks
  rec->Register("hookcommand2", (void*)hook_command2);
  rec->Register("toggleaction", (void*)toggle_action);

  return 1; // success
}
