// Unit tests for reatc_packets.h (Art-Net TimeCode + OSC builders).
// Ported from the former Python tests (tests/test_artnet.py, tests/test_osc.py).
// Build: cmake -S src/extension -B build -DREATC_BUILD_TESTS=ON && ctest

#include "reatc_packets.h"

#include <cstdio>
#include <cstring>

static int g_failed = 0;
static int g_checks = 0;

#define CHECK(cond)                                                        \
  do {                                                                     \
    ++g_checks;                                                            \
    if (!(cond)) {                                                         \
      ++g_failed;                                                          \
      std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);          \
    }                                                                      \
  } while (0)

using namespace reatc;

static void test_artnet()
{
  uint8_t p[ARTNET_TC_LEN];

  build_artnet_timecode(p, 0, 0, 0, 0, 0);
  CHECK(std::memcmp(p, "Art-Net\0", 8) == 0);
  CHECK(p[8] == 0x00 && p[9] == 0x97);   // OpCode 0x9700 little-endian
  CHECK(p[10] == 0x00 && p[11] == 0x0E); // ProtVer 14
  CHECK(p[12] == 0x00);                  // Filler1
  CHECK(p[13] == 0x00);                  // Stream ID default = master

  build_artnet_timecode(p, 12, 34, 56, 23, 2);
  CHECK(p[14] == 23);  // frames
  CHECK(p[15] == 56);  // seconds
  CHECK(p[16] == 34);  // minutes
  CHECK(p[17] == 12);  // hours
  CHECK(p[18] == 2);   // type 29.97DF

  for (int t = 0; t < 4; ++t) {
    build_artnet_timecode(p, 0, 0, 0, 0, t);
    CHECK(p[18] == t);
  }

  build_artnet_timecode(p, 39, 59, 59, 29, 3);  // extended hours (LTC BCD)
  CHECK(p[14] == 29 && p[15] == 59 && p[16] == 59 && p[17] == 39 && p[18] == 3);

  build_artnet_timecode(p, 1, 2, 3, 4, 1, 7);
  CHECK(p[13] == 7);
  build_artnet_timecode(p, 1, 2, 3, 4, 1, 255);
  CHECK(p[13] == 255);
  build_artnet_timecode(p, 1, 2, 3, 4, 1, 256);  // masked to a byte
  CHECK(p[13] == 0);
}

static void test_osc_string()
{
  std::vector<uint8_t> v;
  osc_append_string(v, "/tc");     // 3 chars + NUL = 4
  CHECK(v.size() == 4 && v[3] == 0);
  v.clear();
  osc_append_string(v, "/abc");    // 4 chars + NUL = 5 -> padded to 8
  CHECK(v.size() == 8 && v[4] == 0 && v[7] == 0);
  v.clear();
  osc_append_string(v, "");        // NUL only, padded to 4
  CHECK(v.size() == 4);
}

static void test_osc_message()
{
  const auto m = build_osc_timecode("/tc", 1, 2, 3, 4, 1);
  // "/tc\0" (4) + ",iiiii\0\0" (8) + 5 x int32 (20)
  CHECK(m.size() == 32);
  CHECK(std::memcmp(m.data(), "/tc\0", 4) == 0);
  CHECK(std::memcmp(m.data() + 4, ",iiiii\0\0", 8) == 0);
  const uint8_t args[20] = { 0,0,0,1, 0,0,0,2, 0,0,0,3, 0,0,0,4, 0,0,0,1 };
  CHECK(std::memcmp(m.data() + 12, args, 20) == 0);
  CHECK(m.size() % 4 == 0);

  const auto m2 = build_osc_timecode("/reatc/tc", 23, 59, 59, 29, 3);
  CHECK(m2.size() % 4 == 0);
  CHECK(m2.size() == 12 + 8 + 20);  // "/reatc/tc\0" padded to 12
  CHECK(m2[m2.size() - 1] == 3);
}

static void test_range()
{
  CHECK(tc_in_range(0, 0, 0, 0, 0));
  CHECK(tc_in_range(39, 59, 59, 29, 3));
  CHECK(!tc_in_range(40, 0, 0, 0, 0));
  CHECK(!tc_in_range(0, 60, 0, 0, 0));
  CHECK(!tc_in_range(0, 0, 60, 0, 0));
  CHECK(!tc_in_range(0, 0, 0, 30, 0));
  CHECK(!tc_in_range(0, 0, 0, 0, 4));
  CHECK(!tc_in_range(-1, 0, 0, 0, 0));
}

int main()
{
  test_artnet();
  test_osc_string();
  test_osc_message();
  test_range();
  std::printf("%d/%d checks passed\n", g_checks - g_failed, g_checks);
  return g_failed == 0 ? 0 : 1;
}
