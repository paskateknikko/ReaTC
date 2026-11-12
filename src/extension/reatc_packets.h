/*
 * reatc_packets.h — pure packet builders for Art-Net TimeCode and OSC.
 *
 * No sockets, no REAPER API: kept header-only so the unit test can build it
 * on any platform without the rest of the extension.
 *
 * Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
 */
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace reatc {

/// Timecode type, as used by Art-Net and the ReaTC JSFX.
enum TcType : int { TC_24 = 0, TC_25 = 1, TC_2997DF = 2, TC_30 = 3 };

/// True if H:M:S:F and type are inside the range ReaTC sends
/// (hours 0-39 = full LTC BCD range, frames 0-29, type 0-3).
inline bool tc_in_range(int h, int m, int s, int f, int type)
{
  return h >= 0 && h <= 39 && m >= 0 && m <= 59 && s >= 0 && s <= 59 &&
         f >= 0 && f <= 29 && type >= 0 && type <= 3;
}

constexpr std::size_t ARTNET_TC_LEN = 19;
constexpr int ARTNET_PORT = 6454;

/**
 * Build a 19-byte Art-Net TimeCode (OpTimeCode 0x9700) packet.
 * Layout: "Art-Net\0" | OpCode LE | ProtVer 14 BE | Filler1 | StreamId |
 *         Frames | Seconds | Minutes | Hours | Type
 */
inline void build_artnet_timecode(uint8_t out[ARTNET_TC_LEN], int h, int m,
                                  int s, int f, int type, int stream_id = 0)
{
  static const uint8_t id[8] = { 'A', 'r', 't', '-', 'N', 'e', 't', 0 };
  for (int i = 0; i < 8; ++i) out[i] = id[i];
  out[8]  = 0x00;  // OpCode 0x9700, little-endian
  out[9]  = 0x97;
  out[10] = 0x00;  // ProtVerHi
  out[11] = 0x0E;  // ProtVerLo (14)
  out[12] = 0x00;  // Filler1
  out[13] = static_cast<uint8_t>(stream_id & 0xFF);
  out[14] = static_cast<uint8_t>(f & 0xFF);
  out[15] = static_cast<uint8_t>(s & 0xFF);
  out[16] = static_cast<uint8_t>(m & 0xFF);
  out[17] = static_cast<uint8_t>(h & 0xFF);
  out[18] = static_cast<uint8_t>(type & 0xFF);
}

/// Append an OSC string: bytes + NUL, padded with NULs to a 4-byte boundary.
inline void osc_append_string(std::vector<uint8_t>& out, const std::string& str)
{
  out.insert(out.end(), str.begin(), str.end());
  out.push_back(0);
  while (out.size() % 4 != 0) out.push_back(0);
}

/// Append a big-endian int32.
inline void osc_append_int32(std::vector<uint8_t>& out, int32_t v)
{
  const uint32_t u = static_cast<uint32_t>(v);
  out.push_back(static_cast<uint8_t>(u >> 24));
  out.push_back(static_cast<uint8_t>(u >> 16));
  out.push_back(static_cast<uint8_t>(u >> 8));
  out.push_back(static_cast<uint8_t>(u));
}

/// Build an OSC message `<address> ,iiiii H M S F type`.
inline std::vector<uint8_t> build_osc_timecode(const std::string& address,
                                               int h, int m, int s, int f,
                                               int type)
{
  std::vector<uint8_t> out;
  out.reserve(address.size() + 8 + 8 + 20);
  osc_append_string(out, address);
  osc_append_string(out, ",iiiii");
  osc_append_int32(out, h);
  osc_append_int32(out, m);
  osc_append_int32(out, s);
  osc_append_int32(out, f);
  osc_append_int32(out, type);
  return out;
}

} // namespace reatc
