# ReaTC
<a href="https://www.buymeacoffee.com/paskateknikko" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![GitHub Release](https://img.shields.io/github/v/release/paskateknikko/ReaTC?include_prereleases)](https://github.com/paskateknikko/ReaTC/releases)
[![CI](https://github.com/paskateknikko/ReaTC/actions/workflows/check.yml/badge.svg)](https://github.com/paskateknikko/ReaTC/actions/workflows/check.yml)
[![Release](https://github.com/paskateknikko/ReaTC/actions/workflows/release.yml/badge.svg)](https://github.com/paskateknikko/ReaTC/actions/workflows/release.yml)
[![macOS 10.15+](https://img.shields.io/badge/macOS-10.15%2B-black?logo=apple)](https://github.com/paskateknikko/ReaTC/releases)
[![Windows 10+](https://img.shields.io/badge/Windows-10%2B-black?logo=windows)](https://github.com/paskateknikko/ReaTC/releases)

Sync REAPER with your lighting console using Art-Net, MIDI Timecode, and OSC.

### Utility for lighting programmers using REAPER

![ReaTC overview — JSFX plugin and Lua script running together](images/overview.png)

## Installation

### Via ReaPack (Recommended)

1. Install [ReaPack](https://reapack.com/) if you haven't already
2. Extensions > ReaPack > Import repositories
3. Add this URL:
```
https://github.com/paskateknikko/ReaTC/raw/reapack/index.xml
```
4. Extensions > ReaPack > Browse packages → search "ReaTC" → Install
5. **Restart REAPER** — the C++ extension is only loaded at startup


### Manual Installation

1. Download the latest **ReaTC-x.x.x.zip** from [GitHub Releases](https://github.com/paskateknikko/ReaTC/releases)
2. Extract the zip contents into your REAPER resource folder:
   - **Windows:** `%APPDATA%\REAPER\`
   - **macOS:** `~/Library/Application Support/REAPER/`
   - The zip contains `Scripts/`, `Effects/`, and `UserPlugins/` folders that merge with your existing REAPER resource folder
3. **Restart REAPER** — the C++ extension is only loaded at startup
4. In REAPER: Actions > Show action list > Load ReaScript > select `Scripts/ReaTC/Timecode/reatc.lua`


---


## Features

### Timecode Sources
- **LTC audio decoder** — real-time biphase-mark decoding with adaptive clock recovery; auto-detects frame rate (24/25/29.97DF/30); configurable threshold; varispeed support
- **MTC input** — receives and decodes MIDI Timecode quarter-frame and full-frame SysEx messages; instant locate; 2-frame lag compensation
- **REAPER Timeline** — reads timecode directly from transport position
- **Source priority system** — each source configurable as High/Normal/Low priority with automatic failover

### Timecode Outputs
- **Art-Net TimeCode** — broadcasts SMPTE TC over UDP (port 6454); unicast or broadcast; configurable IP
- **MIDI Timecode (MTC)** — sample-accurate quarter-frame generator via JSFX; no external MIDI library required
- **OSC** — broadcasts SMPTE TC as raw OSC (`/tc ,iiiii H M S F type`) at ~30 fps; configurable destination IP, port, and address
- **LTC audio generator** — encodes timecode to LTC audio with slew-rate shaping matching REAPER's native LTC waveform
- **LTC User Bits** — configurable user bits format (Characters/Date-Timezone) with SMPTE/EBU BGF flag positioning
- **Bake LTC from regions** — standalone tool generates offline LTC WAV files from project regions with per-region TC start, FPS, and output level

### General
- **TC Offset** — user-configurable HH:MM:SS:FF offset applied before all outputs; supports drop-frame wrap-around
- **LTC Diagnostics** — dedicated analysis JSFX with waveform display, bit histogram, timing analysis, and auto-detected frame rate / BGF positioning
- **Network sync status** — Art-Net and OSC toggleable directly from the main window
- **All standard frame rates** — 24fps (Film), 25fps (EBU/PAL), 29.97fps Drop Frame, 30fps (SMPTE)
- **Dark UI** — unified dark style across Lua script and JSFX; scalable TC display
- **Cross-platform** — macOS (10.15+) and Windows (10+); Python 3 standard library only
- **ReaPack compatible** — install via package manager; ReaImGui auto-installed as dependency

## Use Cases

- **Playback sync** — play a REAPER project and broadcast timecode to lighting consoles, video servers, or other devices via Art-Net, OSC, MTC, or LTC
- **Timecode format conversion** — convert between any supported formats without playback (e.g. MTC→LTC, LTC→Art-Net, MTC→OSC); all outputs run whenever valid TC is present, independent of REAPER's transport state
- **Offline LTC rendering** — bake LTC audio from project regions for pre-programmed shows or backup timecode tracks

## Usage

### Setup

ReaTC has two components:

1. **ReaTC Timecode Converter** (JSFX plugin) — handles all TC sources and outputs
2. **ReaTC script** (Lua) — provides the UI and sends Art-Net/OSC over the network

#### Step 1: Add the JSFX plugin

1. Select the track you want to use for timecode (or create a new one)
2. Open the FX browser (click the FX button on the track)
3. Search for **"ReaTC Timecode Converter"** and add it

![JSFX plugin — expanded view with sources and outputs](images/jsfx-expanded.png)

The JSFX plugin handles:
- **Sources**: LTC audio input decoding, MTC MIDI input decoding, REAPER timeline
- **Outputs**: LTC audio encoding, MTC MIDI quarter-frame generation, gmem bridge to the Lua script

When collapsed, the plugin shows a compact timecode display:

![JSFX plugin — compact view](images/jsfx-compact.png)

When resized wider, the plugin shows a compact timecode display:

![JSFX plugin — wide compact view](images/jsfx-wide.png)

Click the ⚙ icon to access JSFX settings (framerate, LTC threshold, output level, user bits, BGF mode):

![JSFX settings dialog](images/jsfx-settings.png)

#### Step 2: Run the Lua script

1. Click the **"Open ReaTC Script"** button in the JSFX Network output section, **or** Actions menu > search "ReaTC" > run **Art-Net and MIDI Timecode sender for REAPER**
2. The script window shows the active timecode and output status
3. Click **Settings** to configure Art-Net and OSC destinations

![Lua script — main window](images/lua.png)

### Configuring TC Sources

In the JSFX plugin UI, enable the sources you need:

- **LTC Input** — route LTC audio to the track; the decoder locks onto the signal automatically
- **MTC Input** — route MIDI containing MTC messages to the track
- **Timeline** — uses REAPER's transport position (enabled by default)

Each source has a **priority** (High / Normal / Low). When multiple sources are locked, the highest-priority source wins. Ties are broken by: LTC > MTC > Timeline.

### Configuring TC Outputs

In the JSFX plugin UI, enable the outputs you need:

- **LTC Audio** — generates LTC audio on the track's output; configure output level with the slider
- **MTC MIDI** — emits quarter-frame messages on the track's MIDI output; configure the MIDI output port via the track's I/O button
- **Script** — writes TC to shared memory (gmem) for the Lua script to read; required for Art-Net and OSC output

![Lua script — settings](images/lua-settings.png)

### Art-Net TC Output

1. Run the ReaTC script and open **Settings**
2. Set the **destination IP** (e.g., `2.0.0.1` for Art-Net unicast, or `2.255.255.255` for broadcast)
3. Enable **Art-Net Output** — packets send whenever valid TC is present

### OSC Timecode Output

1. Run the ReaTC script and open **Settings**
2. Set **destination IP**, **port** (default 9000), and **OSC address** (default `/tc`)
3. Enable **OSC Output** — broadcasts `/tc ,iiiii H M S F type` at ~30 fps

### Bake LTC from Regions

1. Create regions in your REAPER project
2. Run the ReaTC script, open **Settings**, click **Bake LTC from Regions...**
3. Configure TC start and framerate per region, then render
4. Rendered WAV items are placed on a `LTC [rendered]` track

![Bake LTC from Regions — per-region TC start and framerate](images/regions-to-ltc.png)

### LTC User Bits

In the JSFX settings, set **User Bits** format (Characters or Date/Timezone) and enter 4 byte values (0–255). These are embedded in the LTC stream per SMPTE 12M. At 25fps, you can choose between SMPTE (REAPER-compatible) and EBU standard BGF bit positions.

### LTC Diagnostics

Add the **ReaTC LTC Diagnostics** JSFX to the same track (or any track receiving LTC audio) to inspect the signal in detail. Auto-detects frame rate, BGF positioning, and decodes user bits.

![LTC Diagnostics — signal analysis with bit histogram and waveform](images/diagnostics.png)


## Troubleshooting

**"Python 3 not found"**
- macOS: Python 3 is pre-installed on macOS 12.3+. For older versions, install from [python.org](https://python.org).
- Windows: Install from the Microsoft Store (`python3`) or [python.org](https://python.org). Make sure Python is added to your PATH. Restart REAPER after installing.

**"JSFX not detected"**
- Add the **ReaTC Timecode Converter** JSFX to any track (FX browser > search "ReaTC").
- Make sure the JSFX is enabled (not bypassed) and the track is not muted.

**No Art-Net packets being received**
- Check the destination IP matches your console's Art-Net interface.
- Verify your firewall allows outbound UDP on port 6454.
- For broadcast, use the subnet broadcast address (e.g., `2.255.255.255`).

**No OSC messages being received**
- Verify the destination IP, port, and OSC address match the target application's settings.
- Check your firewall allows outbound UDP on the configured port.

**LTC not decoding**
- Route LTC audio to the track with the JSFX. Check the peak meter in the plugin UI.
- Adjust the LTC threshold slider if the signal is too quiet.

## Requirements

- **REAPER 6.32+** (required for `gmem_attach()` shared memory API)
- **ReaImGui** (auto-installed via ReaPack)
- **Python 3** (pre-installed on macOS; Microsoft Store or python.org on Windows)
  No third-party Python packages required.

## License

MIT — see [LICENSE](LICENSE)
