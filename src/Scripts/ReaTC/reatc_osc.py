#!/usr/bin/env python3
# ReaTC — https://github.com/paskateknikko/ReaTC
# Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
#
# OSC TimeCode UDP Daemon
# Persistent process that reads timecode from stdin and sends OSC packets.
# Packet built with raw struct — no external library required.
#
# Usage: python3 reatc_osc.py <dest_ip> <port> <osc_address>
#
# Input format (one line per packet):
#   <hours> <mins> <secs> <frames> <tc_type>
#
# Example stdin:
#   1 23 45 12 1
#   1 23 45 13 1
#
# OSC message sent: <address> ,iiiii  H M S F type  (5 big-endian int32 args)
#
# @noindex
# @version {{VERSION}}

__version__ = "{{VERSION}}"

import sys
import socket
import struct


def osc_string(s):
    """Encode a string as OSC: UTF-8, null-terminated, padded to 4-byte boundary."""
    encoded = s.encode("utf-8") + b"\x00"
    pad = (4 - len(encoded) % 4) % 4
    return encoded + b"\x00" * pad


def build_osc_timecode(address, hours, mins, secs, frames, tc_type):
    """Build a raw OSC message with 5 int32 arguments."""
    return (
        osc_string(address)
        + osc_string(",iiiii")
        + struct.pack(">iiiii", hours, mins, secs, frames, tc_type)
    )


def main():
    if len(sys.argv) < 4:
        print("Usage: reatc_osc.py <dest_ip> <port> <osc_address>", file=sys.stderr)
        sys.exit(1)

    dest_ip     = sys.argv[1]
    port        = int(sys.argv[2])
    osc_address = sys.argv[3]

    # Create socket once at startup (avoid per-packet overhead)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

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

                hours   = int(parts[0])
                mins    = int(parts[1])
                secs    = int(parts[2])
                frames  = int(parts[3])
                tc_type = int(parts[4])

                packet = build_osc_timecode(osc_address, hours, mins, secs, frames, tc_type)
                sock.sendto(packet, (dest_ip, port))

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
