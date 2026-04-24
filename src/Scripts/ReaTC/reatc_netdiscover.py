#!/usr/bin/env python3
# ReaTC — https://github.com/paskateknikko/ReaTC
# Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
#
# Network Interface Discovery
# Prints local IPv4 interfaces as tab-separated rows:
#   <ip>\t<iface>\t<broadcast_or_->\t<netmask>
#
# Locale-independent on Windows (uses iphlpapi.GetAdaptersAddresses via ctypes).
# Parses `ifconfig` output on macOS/Linux.
#
# Usage: python3 reatc_netdiscover.py
#
# Tab-separated because interface friendly names may contain spaces
# ("Wi-Fi 2", "Local Area Connection").
#
# @noindex
# @version {{VERSION}}

from __future__ import annotations

__version__ = "{{VERSION}}"

import ipaddress
import re
import subprocess
import sys


def _prefix_to_mask(prefix: int) -> str:
    """Convert IPv4 prefix length (0-32) to dotted-quad netmask."""
    if prefix <= 0:
        return "0.0.0.0"
    if prefix >= 32:
        return "255.255.255.255"
    mask_int = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF
    return ".".join(str((mask_int >> (24 - 8 * i)) & 0xFF) for i in range(4))


def _broadcast_for(ip: str, mask: str) -> str:
    """Return the broadcast address for an IPv4 host on the given netmask, or '-'."""
    try:
        net = ipaddress.IPv4Network(f"{ip}/{mask}", strict=False)
        return str(net.broadcast_address) if net.prefixlen < 32 else "-"
    except ValueError:
        return "-"


def _list_windows() -> list[tuple[str, str, str, str]]:
    """Enumerate local IPv4 interfaces on Windows via iphlpapi.GetAdaptersAddresses.

    Locale-independent; returns (ip, friendly_name, broadcast, netmask) tuples.
    """
    from ctypes import (
        Structure, POINTER, byref, cast,
        c_ubyte, c_ushort, c_char_p, c_wchar_p,
        c_void_p, c_int, c_uint8,
        windll,  # pyright: ignore[reportAttributeAccessIssue] — Windows-only
    )
    from ctypes.wintypes import ULONG, DWORD

    AF_INET = 2
    ERROR_BUFFER_OVERFLOW = 111
    GAA_FLAG_SKIP_ANYCAST = 0x0002
    GAA_FLAG_SKIP_MULTICAST = 0x0004
    GAA_FLAG_SKIP_DNS_SERVER = 0x0008
    flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER

    class SOCKADDR_IN(Structure):
        _fields_ = [
            ("sin_family", c_ushort),
            ("sin_port", c_ushort),
            ("sin_addr", c_ubyte * 4),
            ("sin_zero", c_ubyte * 8),
        ]

    class SOCKET_ADDRESS(Structure):
        _fields_ = [
            ("lpSockaddr", c_void_p),
            ("iSockaddrLength", c_int),
        ]

    class IP_ADAPTER_UNICAST_ADDRESS(Structure):
        pass

    IP_ADAPTER_UNICAST_ADDRESS._fields_ = [
        ("Length", ULONG),
        ("Flags", DWORD),
        ("Next", POINTER(IP_ADAPTER_UNICAST_ADDRESS)),
        ("Address", SOCKET_ADDRESS),
        ("PrefixOrigin", c_int),
        ("SuffixOrigin", c_int),
        ("DadState", c_int),
        ("ValidLifetime", ULONG),
        ("PreferredLifetime", ULONG),
        ("LeaseLifetime", ULONG),
        ("OnLinkPrefixLength", c_uint8),
    ]

    class IP_ADAPTER_ADDRESSES(Structure):
        pass

    # Only the prefix we read is defined — the struct is larger in Windows headers,
    # but ctypes accesses fields by offset, so trailing fields can be omitted.
    IP_ADAPTER_ADDRESSES._fields_ = [
        ("Length", ULONG),
        ("IfIndex", DWORD),
        ("Next", POINTER(IP_ADAPTER_ADDRESSES)),
        ("AdapterName", c_char_p),
        ("FirstUnicastAddress", POINTER(IP_ADAPTER_UNICAST_ADDRESS)),
        ("FirstAnycastAddress", c_void_p),
        ("FirstMulticastAddress", c_void_p),
        ("FirstDnsServerAddress", c_void_p),
        ("DnsSuffix", c_wchar_p),
        ("Description", c_wchar_p),
        ("FriendlyName", c_wchar_p),
    ]

    GetAdaptersAddresses = windll.iphlpapi.GetAdaptersAddresses
    # Allocate a buffer larger than the struct we defined — the OS writes the
    # full struct, we just don't read past FriendlyName.
    bufsize = ULONG(15 * 1024)
    buf = (c_ubyte * bufsize.value)()
    ret = GetAdaptersAddresses(AF_INET, flags, None,
                               cast(buf, POINTER(IP_ADAPTER_ADDRESSES)),
                               byref(bufsize))
    if ret == ERROR_BUFFER_OVERFLOW:
        buf = (c_ubyte * bufsize.value)()
        ret = GetAdaptersAddresses(AF_INET, flags, None,
                                   cast(buf, POINTER(IP_ADAPTER_ADDRESSES)),
                                   byref(bufsize))
    if ret != 0:
        return []

    results: list[tuple[str, str, str, str]] = []
    ad_ptr = cast(buf, POINTER(IP_ADAPTER_ADDRESSES))
    while ad_ptr:
        ad = ad_ptr.contents
        name = ad.FriendlyName or "?"
        ua_ptr = ad.FirstUnicastAddress
        while ua_ptr:
            ua = ua_ptr.contents
            sa = cast(ua.Address.lpSockaddr, POINTER(SOCKADDR_IN)).contents
            if sa.sin_family == AF_INET:
                ip = ".".join(str(b) for b in sa.sin_addr)
                if not ip.startswith("127."):
                    mask = _prefix_to_mask(ua.OnLinkPrefixLength)
                    bcast = _broadcast_for(ip, mask)
                    results.append((ip, name, bcast, mask))
            ua_ptr = ua.Next
        ad_ptr = ad.Next
    return results


def _list_unix() -> list[tuple[str, str, str, str]]:
    """Enumerate local IPv4 interfaces by parsing `ifconfig` (macOS/Linux)."""
    try:
        out = subprocess.run(["ifconfig"], capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return []

    line_re = re.compile(
        r"\binet\s+(\d+\.\d+\.\d+\.\d+)\s+netmask\s+"
        r"(0x[0-9a-fA-F]+|\d+\.\d+\.\d+\.\d+)"
        r"(?:\s+broadcast\s+(\d+\.\d+\.\d+\.\d+))?"
    )
    results: list[tuple[str, str, str, str]] = []
    iface = "?"
    for line in out.splitlines():
        m = re.match(r"^(\S+):\s", line)
        if m:
            iface = m.group(1).rstrip(":")
            continue
        m = line_re.search(line)
        if not m:
            continue
        ip, mask_raw, bcast = m.group(1), m.group(2), m.group(3)
        if ip.startswith("127."):
            continue
        mask = (str(ipaddress.IPv4Address(int(mask_raw, 16)))
                if mask_raw.startswith("0x") else mask_raw)
        if not bcast:
            bcast = _broadcast_for(ip, mask)
        results.append((ip, iface, bcast, mask))
    return results


def list_interfaces() -> list[tuple[str, str, str, str]]:
    """Return local IPv4 interfaces as (ip, iface, broadcast_or_-, netmask) tuples."""
    return _list_windows() if sys.platform == "win32" else _list_unix()


def main() -> None:
    for ip, iface, bcast, mask in list_interfaces():
        print(f"{ip}\t{iface}\t{bcast}\t{mask}")


if __name__ == "__main__":
    main()
