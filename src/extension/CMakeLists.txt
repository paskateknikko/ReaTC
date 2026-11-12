cmake_minimum_required(VERSION 3.15)

# Read deployment targets from shared config
set(PLATFORMS_ENV "${CMAKE_CURRENT_SOURCE_DIR}/../../build/platforms.env")
if(EXISTS "${PLATFORMS_ENV}")
  file(STRINGS "${PLATFORMS_ENV}" _platform_lines)
  foreach(_line IN LISTS _platform_lines)
    if(_line MATCHES "^([A-Z_]+)=(.+)$")
      set(${CMAKE_MATCH_1} "${CMAKE_MATCH_2}")
    endif()
  endforeach()
endif()

# Fallback defaults if platforms.env is missing
if(NOT DEFINED MACOS_DEPLOYMENT_TARGET)
  set(MACOS_DEPLOYMENT_TARGET "10.15")
endif()
if(NOT DEFINED WINDOWS_MIN_VERSION)
  set(WINDOWS_MIN_VERSION "10")
endif()

# Minimum macOS deployment target. Must be set before project(): project()
# creates an empty CMAKE_OSX_DEPLOYMENT_TARGET cache entry, after which a
# set(... CACHE) is a no-op and the build targets the host macOS version.
# Not FORCEd, so -DCMAKE_OSX_DEPLOYMENT_TARGET=... still overrides it.
set(CMAKE_OSX_DEPLOYMENT_TARGET "${MACOS_DEPLOYMENT_TARGET}" CACHE STRING "Minimum macOS version")

project(reaper_reatc LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(reaper_reatc SHARED reaper_reatc.cpp reatc_net.cpp reatc_output.cpp)

find_package(Threads REQUIRED)
target_link_libraries(reaper_reatc PRIVATE Threads::Threads)

# Version reported by ReaTC_GetVersion() (CI passes the release tag)
set(REATC_VERSION "DEV" CACHE STRING "ReaTC version string")
target_compile_definitions(reaper_reatc PRIVATE REATC_VERSION="${REATC_VERSION}")

if(WIN32)
  target_link_libraries(reaper_reatc PRIVATE ws2_32 iphlpapi winmm)
endif()

# Windows minimum version → _WIN32_WINNT hex value
if(WIN32)
  if(WINDOWS_MIN_VERSION STREQUAL "10")
    set(_WIN32_WINNT_HEX "0x0A00")
  elseif(WINDOWS_MIN_VERSION STREQUAL "8.1")
    set(_WIN32_WINNT_HEX "0x0603")
  elseif(WINDOWS_MIN_VERSION STREQUAL "8")
    set(_WIN32_WINNT_HEX "0x0602")
  elseif(WINDOWS_MIN_VERSION STREQUAL "7")
    set(_WIN32_WINNT_HEX "0x0601")
  else()
    message(FATAL_ERROR "Unknown WINDOWS_MIN_VERSION: ${WINDOWS_MIN_VERSION}")
  endif()
  target_compile_definitions(reaper_reatc PRIVATE _WIN32_WINNT=${_WIN32_WINNT_HEX})
endif()

# No "lib" prefix on any platform
set_target_properties(reaper_reatc PROPERTIES PREFIX "")

# Platform-specific output name and suffix
if(WIN32)
  set_target_properties(reaper_reatc PROPERTIES OUTPUT_NAME "reaper_reatc64")
elseif(APPLE)
  set_target_properties(reaper_reatc PROPERTIES SUFFIX ".dylib")
else()
  set_target_properties(reaper_reatc PROPERTIES SUFFIX ".so")
endif()

# Hidden visibility on Unix (only export ReaperPluginEntry)
if(NOT WIN32)
  set_target_properties(reaper_reatc PROPERTIES
    CXX_VISIBILITY_PRESET hidden
    C_VISIBILITY_PRESET hidden
  )
endif()

# Unit tests for the packet builders (header-only, no REAPER needed)
option(REATC_BUILD_TESTS "Build ReaTC extension unit tests" OFF)
if(REATC_BUILD_TESTS)
  enable_testing()
  add_executable(reatc_tests tests/test_packets.cpp)
  target_include_directories(reatc_tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
  add_test(NAME reatc_tests COMMAND reatc_tests)
endif()
