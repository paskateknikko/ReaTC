/*
 * Minimal REAPER plugin SDK header for non-GUI extensions.
 *
 * Defines only the types needed by reaper_reatc.cpp, avoiding the WDL/SWELL
 * dependency of the full reaper_plugin.h. Derived from the official SDK:
 * https://www.reaper.fm/sdk/plugin/reaper_plugin.h
 *
 * Copyright (C) 2006-2015 Cockos Incorporated — zlib license (see original).
 */

#ifndef _REAPER_PLUGIN_H_
#define _REAPER_PLUGIN_H_

#ifdef _WIN32
  #include <windows.h>
  #define REAPER_PLUGIN_DLL_EXPORT __declspec(dllexport)
#else
  typedef void *HWND;
  typedef void *HINSTANCE;
  typedef unsigned int DWORD;
  #define REAPER_PLUGIN_DLL_EXPORT __attribute__((visibility("default")))
#endif

#define REAPER_PLUGIN_VERSION 0x20E

typedef struct reaper_plugin_info_t
{
  int caller_version;
  HWND hwnd_main;
  int (*Register)(const char *name, void *infostruct);
  void *(*GetFunc)(const char *name);
} reaper_plugin_info_t;

typedef struct
{
  int uniqueSectionId; // 0 = main
  const char *idStr;   // unique action ID string (e.g. "_REATC_MAIN")
  const char *name;    // display name in Actions list
  void *extra;         // reserved
} custom_action_register_t;

// Forward-declare — we only receive a pointer in hookcommand2, never dereference
struct KbdSectionInfo;

#endif // _REAPER_PLUGIN_H_
