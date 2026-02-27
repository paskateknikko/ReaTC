#!/usr/bin/env python3
# ReaTC — https://github.com/paskateknikko/ReaTC
# Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
#
# Art-Net TimeCode UDP Daemon
# Persistent process that reads timecode from stdin and sends Art-Net packets.
#
# Usage: python3 reatc_artnet.py <dest_ip>
#
# Stdin protocol (one line per packet, space-separated integers):
#   <hours> <mins> <secs> <frames> <tc_type>
#
# Field ranges:
#   hours   : 0-23
#   mins    : 0-59
#   secs    : 0-59
#   frames  : 0-29
#   tc_type : 0=24fps  1=25fps  2=29.97DF  3=30fps
#
# The parent process (reatc_outputs.lua) keeps this script alive and writes
# one line per display-frame update.  EOF on stdin causes a clean exit.
#
# Example stdin:
#   1 23 45 12 1
#   1 23 45 13 1
#
# @noindex
# @version 1.1.0

from __future__ import annotations

__version__ = "1.1.0"

import socket
import struct
import sys

ARTNET_PORT = 6454


def build_artnet_timecode(hours: int, mins: int, secs: int, frames: int, tc_type: int) -> bytes:
    """Build Art-Net TimeCode packet (19 bytes).

    @param hours: Hours component (0-23).
    @param mins: Minutes component (0-59).
    @param secs: Seconds component (0-59).
    @param frames: Frame number (0-29).
    @param tc_type: Timecode type (0=24fps, 1=25fps, 2=29.97DF, 3=30fps).
    @return: 19-byte Art-Net TimeCode UDP payload.
    """
    packet = bytearray()

    # ID: "Art-Net\0" (8 bytes)
    packet.extend(b"Art-Net\x00")

    # OpCode: 0x9700 (little-endian)
    packet.extend(struct.pack("<H", 0x9700))

    # ProtVer: 0x000E (14)
    packet.append(0x00)  # ProtVerHi
    packet.append(0x0E)  # ProtVerLo

    # Filler
    packet.append(0x00)
    packet.append(0x00)

    # Timecode
    packet.append(frames & 0xFF)
    packet.append(secs & 0xFF)
    packet.append(mins & 0xFF)
    packet.append(hours & 0xFF)
    packet.append(tc_type & 0xFF)

    return bytes(packet)


def main() -> None:
    """Entry point: read timecode lines from stdin and send Art-Net UDP packets."""
    if len(sys.argv) < 2:
        print("Usage: reatc_artnet.py <dest_ip>", file=sys.stderr)
        sys.exit(1)

    dest_ip = sys.argv[1]

    # Create socket once at startup (avoid per-packet overhead)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

    try:
        # Read lines from stdin until EOF
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue

            try:
                parts = line.split()
                if len(parts) < 5:
                    print(f"artnet: malformed line (need 5 fields): {line!r}", file=sys.stderr)
                    continue

                hours = int(parts[0])
                mins = int(parts[1])
                secs = int(parts[2])
                frames = int(parts[3])
                tc_type = int(parts[4])

                if not (0 <= hours <= 23 and 0 <= mins <= 59
                        and 0 <= secs <= 59 and 0 <= frames <= 29
                        and 0 <= tc_type <= 3):
                    print(f"artnet: TC out of range: {line!r}", file=sys.stderr)
                    continue

                packet = build_artnet_timecode(hours, mins, secs, frames, tc_type)
                sock.sendto(packet, (dest_ip, ARTNET_PORT))

            except (ValueError, IndexError):
                print(f"artnet: parse error: {line!r}", file=sys.stderr)
                continue

    except KeyboardInterrupt:
        pass
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        sock.close()


if __name__ == "__main__":
    main()
