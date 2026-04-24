#!/usr/bin/env python3
# ReaTC — https://github.com/paskateknikko/ReaTC
# Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
#
# Art-Net TimeCode UDP Daemon
# Reads "H M S F tc_type" lines from stdin and sends Art-Net TimeCode packets.
#
# Usage:
#   python3 reatc_artnet.py <dest_ip>[,<dest_ip>...] [--src-ip IP]
#
# `dest_ip`   : one address or a comma-separated list (multi-unicast)
# `--src-ip`  : bind the socket to this local IPv4, so broadcasts/directed
#               broadcasts leave via the chosen NIC instead of the OS default
#
# Interface discovery lives in reatc_netdiscover.py.
#
# tc_type: 0=24fps  1=25fps  2=29.97DF  3=30fps
#
# @noindex
# @version {{VERSION}}

from __future__ import annotations

__version__ = "{{VERSION}}"

import argparse
import socket
import struct
import sys

ARTNET_PORT = 6454


def build_packet(h: int, m: int, s: int, f: int, tc_type: int) -> bytes:
    """Build a 19-byte Art-Net TimeCode packet."""
    return (
        b"Art-Net\x00"                     # ID (8)
        + struct.pack("<H", 0x9700)          # OpCode (2)
        + b"\x00\x0E\x00\x00"                # ProtVer 14 + filler (4)
        + bytes((f, s, m, h, tc_type))       # Timecode (5)
    )


def run(dest_ips: list[str], src_ip: str | None) -> None:
    """Open UDP socket, optionally bind, then stream packets from stdin."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

    if src_ip:
        try:
            sock.bind((src_ip, 0))
        except OSError as e:
            print(f"artnet: bind {src_ip} failed: {e}", file=sys.stderr)

    try:
        for line in sys.stdin:
            parts = line.split()
            if len(parts) != 5:
                continue
            try:
                h, m, s, f, tc = (int(x) for x in parts)
            except ValueError:
                continue
            if not (0 <= h <= 39 and 0 <= m <= 59 and 0 <= s <= 59
                    and 0 <= f <= 29 and 0 <= tc <= 3):
                continue
            pkt = build_packet(h, m, s, f, tc)
            for dest in dest_ips:
                sock.sendto(pkt, (dest, ARTNET_PORT))
    finally:
        sock.close()


def main() -> None:
    p = argparse.ArgumentParser(prog="reatc_artnet.py")
    p.add_argument("dest_ip",
                   help="Destination IP, or comma-separated list")
    p.add_argument("--src-ip", dest="src_ip", default=None,
                   help="Local IPv4 to bind the sending socket to")
    args = p.parse_args()

    dests = [ip.strip() for ip in args.dest_ip.split(",") if ip.strip()]
    if not dests:
        p.error("no valid destination IPs")

    try:
        run(dests, args.src_ip)
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
