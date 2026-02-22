# ReaTC
Sync REAPER with your lighting console using Art-Net and MIDI timecode.


### Utility for lighting programmers using REAPER

Send Art-Net TimeCode and MIDI TimeCode (MTC) from REAPER to lighting consoles like grandMA3, Avolites, ETC, and other compatible devices.

## Features

- **Real-time TC transmission** from REAPER transport position or LTC audio input
- **Multiple TC sources**:
  - REAPER transport position (default)
  - LTC audio decoding from any track (via Lua + REAPER audio accessor)
- **Art-Net TimeCode output** via UDP (port 6454)
- **MIDI TimeCode (MTC) output** via virtual or hardware MIDI ports
- **All standard frame rates**: 24fps (Film), 25fps (EBU/PAL), 29.97fps (Drop Frame), 30fps (SMPTE)
- **Unicast or broadcast** destination for Art-Net
- **Large TC monitor display** with visual feedback
- **Cross-platform**: Windows and macOS
- **ReaPack compatible** for easy installation

## Requirements

- **REAPER 6.32+** (required for `gmem_attach()` shared memory API)
- **ReaImGui** — install via ReaPack: Extensions → ReaPack → Browse packages → search "ReaImGui" (ReaTeam Extensions)
- **Python 3** (pre-installed on macOS; install from Microsoft Store or https://python.org on Windows)
- **python-rtmidi** (optional, for MTC output): automatically installed on first MTC enable via `pip3 install python-rtmidi`

## Installation

### Via ReaPack (Recommended)

1. Install [ReaPack](https://reapack.com/) if you haven't already
2. Extensions > ReaPack > Import repositories
3. Add: `https://github.com/paskateknikko/ReaTC/raw/reapack/index.xml`
4. Extensions > ReaPack > Browse packages
5. Search for "ReaTC" and click Install

**Note:** The index.xml file is automatically published to the reapack branch on each release.

### Manual Installation

1. Download or clone this repository
2. Copy the `dist/Scripts/ReaTC` folder to your REAPER Scripts directory:
   - **Windows**: `%APPDATA%\REAPER\Scripts\`
   - **macOS**: `~/Library/Application Support/REAPER/Scripts/`
3. In REAPER: Actions > Show action list > Load ReaScript
4. Select `ReaTC.lua`

### Windows Python Setup

If Python 3 is not installed:
1. Download from [python.org](https://www.python.org/downloads/) or Microsoft Store
2. During installation, check "Add Python to PATH"
3. Restart REAPER

## Usage

### Basic Art-Net TC Output

1. **Run the script** from REAPER's Actions menu
2. **Set destination IP**:
   - Enter specific IP (e.g., `192.168.1.100`) for unicast
   - Default: `2.0.0.1` (multicast)
3. **Select frame rate** matching your show/console
4. **Enable "Art-Net Output"** to begin transmission (once enabled, packets send at ~25/sec when playback is active)
5. **Adjust offset** if needed to sync with external devices

### MIDI Timecode (MTC) Output

1. Enable "Enable MTC" checkbox
2. Select MIDI port or use "Virtual Port" (creates "REAPER MTC Out")
3. TC will be sent via MIDI quarter-frame messages
4. Full-frame messages sent on play/stop for instant sync

### LTC Audio Input

1. Enable "Use LTC" checkbox
2. Select the track containing LTC audio
3. Script decodes at ~44.1kHz; adjust threshold slider if decoding is unreliable
4. When locked, TC display shows "LOCKED" in green

## License

MIT License — see [LICENSE](LICENSE) for details.