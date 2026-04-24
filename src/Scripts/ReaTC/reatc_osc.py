#!/usr/bin/env python3
# ReaTC — https://github.com/paskateknikko/ReaTC
# Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
#
# OSC TimeCode UDP Daemon
# Persistent process that reads timecode from stdin and sends OSC packets.
# Packet built with raw struct — no external library required.
#
# Usage:
#   python3 reatc_osc.py <dest_ip> <port> <osc_address> [--src-ip IP]
#
# `--src-ip` binds the sending socket to that local IPv4 address. Without it,
# the OS default route is used. Set this if you have multiple interfaces and
# the packet needs to leave via a specific one.
#
# Stdin protocol (one line per packet, space-separated integers):
#   <hours> <mins> <secs> <frames> <tc_type>
#
# Field ranges:
#   hours   : 0-39
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
# OSC message sent: <address> ,iiiii  H M S F type  (5 big-endian int32 args)
#
# @noindex
# @version {{VERSION}}

from __future__ import annotations

__version__ = "{{VERSION}}"

import argparse
import socket
import struct
import sys


def osc_string(s: str) -> bytes:
    """Encode a string as OSC: UTF-8, null-terminated, padded to 4-byte boundary.

    @param s: The string to encode.
    @return: Null-terminated, 4-byte-aligned bytes.
    """
    encoded = s.encode("utf-8") + b"\x00"
    pad = (4 - len(encoded) % 4) % 4
    return encoded + b"\x00" * pad


def build_osc_timecode(address: str, hours: int, mins: int, secs: int, frames: int, tc_type: int) -> bytes:
    """Build a raw OSC message with 5 int32 arguments.

    @param address: OSC address pattern (e.g. "/reatc/tc").
    @param hours: Hours component (0-39).
    @param mins: Minutes component (0-59).
    @param secs: Seconds component (0-59).
    @param frames: Frame number (0-29).
    @param tc_type: Timecode type (0=24fps, 1=25fps, 2=29.97DF, 3=30fps).
    @return: Complete OSC message bytes ready for UDP transmission.
    """
    return (
        osc_string(address)
        + osc_string(",iiiii")
        + struct.pack(">iiiii", hours, mins, secs, frames, tc_type)
    )


def main() -> None:
    """Entry point: read timecode lines from stdin and send OSC UDP packets."""
    parser = argparse.ArgumentParser(prog="reatc_osc.py", add_help=True)
    parser.add_argument("dest_ip")
    parser.add_argument("port", type=int)
    parser.add_argument("osc_address")
    parser.add_argument("--src-ip", dest="src_ip", default=None,
                        help="Bind send socket to this local IPv4 address")
    args = parser.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

    if args.src_ip:
        try:
            sock.bind((args.src_ip, 0))
            print(f"osc: bound to source {args.src_ip}", file=sys.stderr)
        except OSError as e:
            print(f"osc: bind to {args.src_ip} failed: {e} (continuing unbound)",
                  file=sys.stderr)

    print(f"osc: sending to {args.dest_ip}:{args.port} {args.osc_address}",
          file=sys.stderr)

    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue

            try:
                parts = line.split()
                if len(parts) < 5:
                    print(f"osc: malformed line (need 5 fields): {line!r}", file=sys.stderr)
                    continue

                hours   = int(parts[0])
                mins    = int(parts[1])
                secs    = int(parts[2])
                frames  = int(parts[3])
                tc_type = int(parts[4])

                if not (0 <= hours <= 39 and 0 <= mins <= 59
                        and 0 <= secs <= 59 and 0 <= frames <= 29
                        and 0 <= tc_type <= 3):
                    print(f"osc: TC out of range: {line!r}", file=sys.stderr)
                    continue

                packet = build_osc_timecode(args.osc_address, hours, mins, secs, frames, tc_type)
                sock.sendto(packet, (args.dest_ip, args.port))

            except (ValueError, IndexError):
                print(f"osc: parse error: {line!r}", file=sys.stderr)
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
