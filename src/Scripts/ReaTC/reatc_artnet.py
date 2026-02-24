#!/usr/bin/env python3
# ReaTC — https://github.com/paskateknikko/ReaTC
# Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
#
# Art-Net TimeCode UDP Daemon
# Persistent process that reads timecode from stdin and sends Art-Net packets
#
# Usage: python3 reatc_artnet.py <dest_ip>
#
# Input format (one line per packet):
#   <hours> <mins> <secs> <frames> <tc_type>
#
# Example stdin:
#   1 23 45 12 1
#   1 23 45 13 1
#
# @noindex
# @version {{VERSION}}

__version__ = "{{VERSION}}"

import socket
import struct
import sys

ARTNET_PORT = 6454


def build_artnet_timecode(hours, mins, secs, frames, tc_type):
    """Build Art-Net TimeCode packet (19 bytes)"""
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


def main():
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
                    continue

                hours = int(parts[0])
                mins = int(parts[1])
                secs = int(parts[2])
                frames = int(parts[3])
                tc_type = int(parts[4])

                packet = build_artnet_timecode(hours, mins, secs, frames, tc_type)
                sock.sendto(packet, (dest_ip, ARTNET_PORT))

            except (ValueError, IndexError):
                # Skip malformed lines
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
