-- LDoc configuration for ReaTC
project = "ReaTC"
title = "ReaTC API Documentation"
description = "Lua API documentation for ReaTC — REAPER timecode synchronization"

file = "src/Scripts/ReaTC"
dir = "docs/lua"

-- Exclude standalone scripts from module docs (they have their own entry points)
exclude = { "reatc_regions_to_ltc.lua" }

-- Use three-dash style (---) for doc comments
style = "!lua"
format = "markdown"
