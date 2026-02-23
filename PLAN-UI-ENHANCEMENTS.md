# Plan: UI Enhancements for ReaTC

## Context
The main window (`reatc_ui.lua`) is functional but visually sparse. Two explicit requests:
1. Enforce a minimum window size (currently unconstrained)
2. Move settings from inline view-swap to a floating popup modal

All changes are in `src/Scripts/ReaTC/reatc_ui.lua` only.

---

## Changes

### 1. Minimum window size
Add `ImGui.SetNextWindowSizeConstraints()` before `ImGui.Begin()` in `draw_ui()`.

```lua
function M.draw_ui()
  ImGui.SetNextWindowSizeConstraints(ctx, 480, 160, 1e9, 1e9)
  local visible, open = ImGui.Begin(ctx, 'ReaTC v' .. core.VERSION, true)
  ...
```

Min values: **480 × 160 px** — enough to show the 72pt TC string without clipping.

---

### 2. Settings as a popup modal
Replace the `show_settings` view-swap with a proper ImGui popup modal that floats over the main window.

**Current pattern:**
- `Settings` button sets `s.show_settings = true`
- `draw_ui()` calls either `draw_main()` or `draw_settings()` — full view replacement

**New pattern:**
- `Settings` button calls `ImGui.OpenPopup(ctx, 'Settings##popup')`
- `draw_main()` stays visible underneath
- After `draw_main()`, always attempt `ImGui.BeginPopupModal(ctx, 'Settings##popup', true, ...)`:
  - If visible → call `draw_settings()` content + `ImGui.EndPopup(ctx)`
  - Close button inside settings calls `ImGui.CloseCurrentPopup(ctx)`
  - Escape key and clicking outside automatically close the modal
- Remove `s.show_settings` state and the mini-TC header in `draw_settings()`

The settings content function stays the same — only the framing changes.

---

### 3. Output status indicators on main view
Add a compact row between the status line and Settings button showing which outputs are active:
```
● Art-Net   ● MTC
```
Green dot when enabled+active, dim gray when disabled. Gives instant visual feedback without opening settings.

### 4. Dim the frames field
Render the frames field (`:FF`) in a slightly dimmer color to distinguish sub-second from timecode address. Requires splitting `tc_str` and doing two `TextColored` + `SameLine` calls within the font push.

---

## Critical file
- `src/Scripts/ReaTC/reatc_ui.lua` — all changes here

## State cleanup
- Remove `s.show_settings` from use in `draw_ui()` (can leave in state table for backwards compat if saved, but no longer needed for logic)

## Verification
1. `make build`
2. Load `dist/Scripts/ReaTC/ReaTC.lua` in REAPER
3. Resize window below 480px wide — should snap back
4. Click Settings → modal opens over main TC display
5. Press Escape or click outside → modal closes
6. All settings controls work identically to before
