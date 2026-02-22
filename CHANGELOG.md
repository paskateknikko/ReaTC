# Changelog

All notable changes to ReaTC will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.0.2] - 2026-02-22

### Added

- Automated GitHub Releases workflow that builds and packages ReaTC on version tags
- ReaPack index metadata improvements with correct repository URLs and all script sources
- Release zip artifact generation for GitHub Releases

### Changed

- Build scripts tracked in git for CI compatibility
- ReaPack install URL updated to the correct GitHub repository


## [0.0.1] - 2026-02-22

### Features

- **Real-time TC transmission** from REAPER transport position or LTC audio input
- **Multiple TC sources**:
  - REAPER transport position (default)
  - LTC audio decoding from any track via Lua + REAPER audio accessor
- **Art-Net TimeCode output** via UDP (port 6454)
- **MIDI TimeCode (MTC) output** via virtual or hardware MIDI ports
- **All standard frame rates**: 24fps (Film), 25fps (EBU/PAL), 29.97fps (Drop Frame), 30fps (SMPTE)
- **Unicast or broadcast** destination for Art-Net
- **Large TC monitor display** with visual feedback
- **Cross-platform support**: Windows and macOS
- **ReaPack compatible** for easy installation via package manager

### Requirements

- REAPER 6.0 or higher
- Python 3 (pre-installed on macOS; download from https://python.org on Windows)
- python-rtmidi (optional, for MTC output) - auto-installed on first MTC enable

### Technical Details

- **Art-Net Implementation**: Standard DMX512-over-Ethernet protocol
- **Frame Rate Support**: SMPTE and EBU standards
- **LTC Decoding**: Sub-frame accuracy timecode detection from audio
- **MIDI**: Full Frame and Quarter Frame messages per MTC spec
