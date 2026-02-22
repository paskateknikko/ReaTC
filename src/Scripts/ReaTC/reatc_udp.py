#!/usr/bin/env python3
# ReaTC — https://github.com/<org>/ReaTC
# Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
#
# Art-Net TimeCode UDP Sender
# Called from REAPER Lua script to send Art-Net packets
#
# Usage: python3 reatc_udp.py <dest_ip> <hours> <mins> <secs> <frames> <type>
#
# Example: python3 reatc_udp.py 192.168.1.100 1 23 45 12 1

__version__ = "{{VERSION}}"

import sys
import socket
import struct

ARTNET_PORT = 6454

def build_artnet_timecode(hours, mins, secs, frames, tc_type):
    """Build Art-Net TimeCode packet (19 bytes)"""
    packet = bytearray()

    # ID: "Art-Net\0" (8 bytes)
    packet.extend(b'Art-Net\x00')

    # OpCode: 0x9700 (little-endian)
    packet.extend(struct.pack('<H', 0x9700))

    # ProtVer: 0x000E (14) - high byte first in spec but we pack as bytes
    packet.append(0x00)  # ProtVerHi
    packet.append(0x0E)  # ProtVerLo (14)

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

def send_timecode(dest_ip, hours, mins, secs, frames, tc_type):
    """Send Art-Net TimeCode packet"""
    packet = build_artnet_timecode(hours, mins, secs, frames, tc_type)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

    try:
        sock.sendto(packet, (dest_ip, ARTNET_PORT))
        return True
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return False
    finally:
        sock.close()

def main():
    if len(sys.argv) < 7:
        print("Usage: reatc_udp.py <ip> <hours> <mins> <secs> <frames> <type>", file=sys.stderr)
        sys.exit(1)

    dest_ip = sys.argv[1]
    hours = int(sys.argv[2])
    mins = int(sys.argv[3])
    secs = int(sys.argv[4])
    frames = int(sys.argv[5])
    tc_type = int(sys.argv[6])

    if send_timecode(dest_ip, hours, mins, secs, frames, tc_type):
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == '__main__':
    main()
