# ReaTC

Sync REAPER with your lighting console using Art-Net, MIDI Timecode, and OSC.

## Timecode Sources

- **LTC audio** — decode Linear Timecode from any audio track via JSFX; adaptive clock recovery for varispeed support
- **MIDI Timecode (MTC)** — decode incoming MTC quarter-frame and full-frame SysEx via JSFX
- **REAPER Timeline** — read timecode directly from the transport position

Each source has a configurable priority (High / Normal / Low) with automatic failover.

## Timecode Outputs

- **Art-Net TimeCode** — broadcast SMPTE TC over UDP to lighting consoles
- **MIDI Timecode (MTC)** — sample-accurate quarter-frame output via JSFX
- **OSC** — configurable OSC timecode output over UDP
- **LTC audio** — encode timecode as audio on a track via JSFX
- **Bake LTC from regions** — render offline LTC WAV files from project regions

## Features

- All standard frame rates (24, 25, 29.97DF, 30)
- TC Offset — user-configurable HH:MM:SS:FF offset applied before all outputs
- Source priority with automatic failover between LTC, MTC, and Timeline
- Network sync status with packet counts and daemon health indicators
- Cross-platform (macOS 10.15+, Windows 10+)

## Requirements

- REAPER 6.32+
- ReaImGui (auto-installed via ReaPack)
- Python 3 (standard library only)

## Links

- [GitHub](https://github.com/paskateknikko/ReaTC)
- [License: MIT](https://github.com/paskateknikko/ReaTC/blob/main/LICENSE)
