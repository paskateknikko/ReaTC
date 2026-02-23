# ReaTC — Known Issues & Improvements

## Critical

### 1. Drop-frame TC formula wrong at 10-minute boundaries
**Files:** `reatc_ltc.jsfx` (`tc_from_pos_df`), `reatc_core.lua` (`seconds_to_timecode`)

```
tf = total + 18*d + 2*floor((mm - 2) / 1798)
```

When `mm` is 0 or 1 (first 2 frames of every 10-minute block), `floor((mm - 2) / 1798)` evaluates to `-1`, making `tf` 2 less than expected. At `pos = 0` (project start), `tf = -2` — producing garbage TC (`23:59:59;28` in Lua, undefined in EEL2). Also fires at 10:00, 20:00, 30:00, etc., causing a 2-frame glitch.

**Fix:** `max(0, floor((mm - 2) / 1798))` or guard `mm < 2`.

### 2. `slider_automate(slider10)` passes value not bitmask
**File:** `reatc_ltc.jsfx` @gfx interaction

```jsfx
slider_automate(slider10);  // slider10 is 0 or 1
```

`slider_automate()` expects a bitmask where bit N corresponds to slider N+1. Passing `0` does nothing; passing `1` automates slider1 (Hours) instead of slider10. Mode changes are not recorded to automation.

**Fix:** `slider_automate(1<<9)` or `slider_automate(0x200)`.

---

## Medium

### 3. Negative `play_position` not handled
**Files:** `reatc_ltc.jsfx` (`tc_from_pos_ndf`, `tc_from_pos_df`), `reatc_core.lua`

REAPER allows cursor positions before project start (negative). `floor(pos * fps_int)` produces negative frame counts; `%` on negatives is undefined in EEL2 and wraps in Lua. Results in garbage H/M/S/F values.

**Fix:** Clamp `pos = max(0, pos)` at the top of both TC conversion functions.

### 4. No sample rate change detection
**File:** `reatc_ltc.jsfx`

`update_params()` caches timing constants from `srate` but is only called from `@init` and `@slider`. If the sample rate changes mid-session (audio device switch), decoder thresholds and encoder rate will be wrong until a slider is moved.

**Fix:** Compare `srate` to a cached value at the top of `@block`; call `update_params()` on change.

### 5. Per-sample peak decay uses block-size exponent
**File:** `reatc_ltc.jsfx` @sample, Transport mode branch

```jsfx
peak_level *= exp(log(0.316) * samplesblock / srate);
```

This is inside `@sample` but uses `samplesblock` (e.g., 512). Applied per sample, the effective decay is `0.316^512` per block — zeroing the peak instantly.

**Fix:** Use `1.0 / srate` instead of `samplesblock / srate` inside `@sample`.

### 6. Stale MediaTrack pointer after track deletion
**File:** `reatc_ltc.lua` (`update_jsfx`)

`state.ltc_track` is a cached `MediaTrack` pointer. If the user deletes the track, the handle becomes dangling. `TrackFX_GetParam` / `TrackFX_SetParam` calls fail silently, and the script appears to work but never receives decoded TC.

**Fix:** Add `reaper.ValidatePtr(track, "MediaTrack*")` check before accessing.

### 7. LTC re-clock described but not implemented
**File:** `reatc_ltc.jsfx` header comments

The description says: *"Source mode 1 – LTC Input: decodes LTC from incoming audio and re-clocks / mirrors it on the output."* But the LTC encoder only runs when `src_mode == 0` (Transport). In LTC Input mode raw audio passes through — no re-clocked LTC output is generated.

**Fix:** Either enable the encoder in LTC Input mode or update the description to match actual behavior.

---

## Low Priority

### 8. Art-Net spawns Python per packet (~30/s)
**File:** `reatc_outputs.lua` (`send_artnet`)

Each Art-Net packet spawns a fresh Python process via `io.popen()` — fork+exec, Python startup, socket import, one UDP send, exit. ~30 times per second. Significant overhead and scheduling jitter.

**Fix:** Convert to a long-running daemon (like MTC), or use a persistent socket approach.

### 9. Track identified by index, not GUID
**File:** `reatc_core.lua` (settings persistence)

`ltc_track_idx` is a 0-based index saved/loaded via ExtState. If tracks are added, removed, or reordered between sessions, `GetTrack(0, idx)` returns a different track silently.

**Fix:** Persist the track GUID instead of index; resolve at load time.

### 10. `pip install` blocks UI thread
**File:** `reatc_core.lua` (`try_install_rtmidi`)

`os.execute(q .. ' -m pip install python-rtmidi')` runs synchronously. On slow connections this freezes REAPER for 10+ seconds with no progress indication.

### 11. Redundant `build_enc_frame()` in @slider
**File:** `reatc_ltc.jsfx`

`@slider` calls `build_enc_frame()` but the encoder frame depends on `enc_h/m/s/f` set in `@block`. The frame built from stale values is immediately overwritten. Harmless but unnecessary.

### 12. `dec_seq` bumped every @block in Transport mode
**File:** `reatc_ltc.jsfx`

`dec_seq` increments every `@block` (~94 times/s at 48kHz/512 samples), but TC only changes at frame rate (24–30 Hz). ~60–70% of Lua slider reads triggered by seq changes are redundant.

**Fix:** Only increment when `enc_h/m/s/f` actually change from previous values.

### 13. @gfx/@sample variable sharing (benign races)
**File:** `reatc_ltc.jsfx`

Variables like `ltc_detect_samples`, `fps_type`, `ltc_rate_mismatch`, and `dec_valid` are written in `@sample`/`@block` (audio thread) and read in `@gfx` (GUI thread) without synchronization. In practice this only causes momentarily stale display values.

### 14. No IP address validation
**File:** `reatc_core.lua`

`state.dest_ip` is loaded from persistent config and passed directly to the Python UDP script. A malformed IP causes silent Art-Net send failures. Validation on save/load would provide earlier feedback.

### 15. NDF division by float fps
**File:** `reatc_core.lua` (`seconds_to_timecode`)

NDF path divides by `fps` from `FPS_VAL = {24, 25, 29.97, 30}`. For NDF rates these are always integers so no actual bug, but using `int_fps` from `FPS_INT` would express intent more clearly.
