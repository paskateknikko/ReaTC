// Unit tests for reatc_packets.h (Art-Net TimeCode + OSC builders, frame
// math) and reatc_clock.h (per-frame send scheduling).
// Ported from the former Python tests (tests/test_artnet.py, tests/test_osc.py).
// Build: cmake -S src/extension -B build -DREATC_BUILD_TESTS=ON && ctest

#include "reatc_clock.h"
#include "reatc_packets.h"

#include <cstdio>
#include <cmath>
#include <cstring>
#include <vector>

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

static void test_frames()
{
  int h, m, s, f;
  // Round trip every frame of the first 11 minutes, all types (covers the
  // 29.97DF minute and 10-minute boundaries).
  for (int type = 0; type < 4; ++type) {
    bool ok = true;
    for (int64_t n = 0; n < 11 * 60 * 30; ++n) {
      frames_to_tc(n, type, h, m, s, f);
      if (!tc_in_range(h, m, s, f, type) || tc_to_frames(h, m, s, f, type) != n) ok = false;
    }
    CHECK(ok);
  }

  // 29.97DF drops labels 00 and 01 at each minute except every 10th
  frames_to_tc(1799, TC_2997DF, h, m, s, f);
  CHECK(h == 0 && m == 0 && s == 59 && f == 29);
  frames_to_tc(1800, TC_2997DF, h, m, s, f);
  CHECK(h == 0 && m == 1 && s == 0 && f == 2);
  frames_to_tc(17982, TC_2997DF, h, m, s, f);
  CHECK(h == 0 && m == 10 && s == 0 && f == 0);
  CHECK(tc_to_frames(1, 0, 0, 0, TC_2997DF) == 107892);  // 6 x 17982

  // Wrap at 40 hours (LTC BCD max)
  frames_to_tc(tc_to_frames(39, 59, 59, 24, TC_25) + 1, TC_25, h, m, s, f);
  CHECK(h == 0 && m == 0 && s == 0 && f == 0);
  frames_to_tc(tc_wrap_frames(TC_2997DF) - 1, TC_2997DF, h, m, s, f);
  CHECK(h == 39 && m == 59 && s == 59 && f == 29);
  frames_to_tc(-1, TC_30, h, m, s, f);
  CHECK(h == 39 && m == 59 && s == 59 && f == 29);
}

/// Run the clock from t0 to t1 (keep t1 off a frame boundary), waking
/// exactly when it asks; return the frames it sent.
static std::vector<int64_t> run_clock(const TcAnchor& a, ClockState& st,
                                      double t0, double t1)
{
  std::vector<int64_t> sent;
  double t = t0;
  while (t < t1) {
    const ClockDecision d = clock_step(a, st, t);
    if (d.send) sent.push_back(d.frame);
    t = d.next > t ? d.next : t + 1e-4;
  }
  return sent;
}

static void test_clock()
{
  TcAnchor a;
  a.valid = true;
  a.running = true;
  a.type = TC_25;
  a.frame = 1000;
  a.start = 10.0;

  // Running: every frame exactly once, no gaps (the bug: every other frame)
  {
    ClockState st;
    const auto sent = run_clock(a, st, 10.0, 10.38);  // 10 frames at 25 fps
    CHECK(sent.size() == 10);
    bool seq = true;
    for (std::size_t i = 0; i < sent.size(); ++i)
      if (sent[i] != 1000 + int64_t(i)) seq = false;
    CHECK(seq);
  }

  // Sent on the boundary: frame 1003 is due at 10.12 s
  {
    ClockState st;
    ClockDecision d = clock_step(a, st, 10.0);
    CHECK(d.send && d.frame == 1000);
    CHECK(std::fabs(d.next - 10.04) < 1e-9);
    d = clock_step(a, st, 10.039);  // early wake: nothing new yet
    CHECK(!d.send);
    d = clock_step(a, st, 10.12);
    CHECK(d.send && d.frame == 1003);
  }

  // A late anchor (script saw the frame a little late) never steps back
  {
    ClockState st;
    run_clock(a, st, 10.0, 10.2);       // sent up to 1004
    TcAnchor late = a;
    late.frame = 1004;
    late.start = 10.19;                 // says 1004 started 30 ms late
    const ClockDecision d = clock_step(late, st, 10.2);
    CHECK(!d.send);                     // 1004 already sent
    CHECK(std::fabs(d.next - 10.23) < 1e-9);
  }

  // A jump (locate) is sent immediately
  {
    ClockState st;
    run_clock(a, st, 10.0, 10.1);
    TcAnchor jump = a;
    jump.frame = 5000;
    jump.start = 10.1;
    const ClockDecision d = clock_step(jump, st, 10.1);
    CHECK(d.send && d.frame == 5000);
  }

  // Held (paused): repeat the same frame once per period
  {
    ClockState st;
    TcAnchor held = a;
    held.running = false;
    const auto sent = run_clock(held, st, 10.0, 10.18);
    CHECK(sent.size() == 5);
    bool same = true;
    for (auto fr : sent) if (fr != 1000) same = false;
    CHECK(same);
  }

  // Stale anchor (no update for > MAX_EXTRAPOLATION): stop advancing
  {
    ClockState st;
    const ClockDecision d = clock_step(a, st, 10.0 + MAX_EXTRAPOLATION + 0.1);
    CHECK(d.send && d.frame == 1000);
  }

  // Invalid: nothing sent; next valid frame is sent at once
  {
    ClockState st;
    TcAnchor inv = a;
    inv.valid = false;
    CHECK(!clock_step(inv, st, 10.0).send);
    CHECK(clock_step(a, st, 10.0).send);
  }

  // 29.97DF period
  {
    ClockState st;
    TcAnchor df = a;
    df.type = TC_2997DF;
    const auto sent = run_clock(df, st, 10.0, 10.0 + 29.5 * 1001.0 / 30000.0);
    CHECK(sent.size() == 30);
  }
}

int main()
{
  test_artnet();
  test_osc_string();
  test_osc_message();
  test_range();
  test_frames();
  test_clock();
  std::printf("%d/%d checks passed\n", g_checks - g_failed, g_checks);
  return g_failed == 0 ? 0 : 1;
}
