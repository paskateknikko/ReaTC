/*
 * reatc_clock.h — frame clock for ReaTC network output.
 *
 * The Lua script only runs ~30 times per second, which is too coarse to send
 * one packet per frame (at 25 fps a 40 ms throttle checked every ~33 ms lands
 * on every other frame). Instead the script hands the extension an *anchor*:
 * the current frame, when it started, and whether TC is advancing. The
 * extension's sender thread extrapolates from that anchor and sends each
 * frame on its own boundary, re-locking whenever a new anchor arrives.
 *
 * Pure logic, no threads or sockets: covered by tests/test_packets.cpp.
 *
 * Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
 */
#pragma once

#include <cmath>
#include <cstdint>

#include "reatc_packets.h"

namespace reatc {

/// How far past its anchor the clock may run without a fresh anchor before
/// it stops extrapolating and goes silent (Lua stalled or the JSFX stopped
/// processing while TC was running).
constexpr double MAX_EXTRAPOLATION = 0.5;

/// Latest TC reported by the script.
struct TcAnchor {
  bool valid = false;    ///< a TC source is active
  bool running = false;  ///< TC is advancing at normal speed
  int type = TC_25;      ///< TcType
  int64_t frame = 0;     ///< frame count (tc_to_frames) of the current frame
  double start = 0.0;    ///< clock time (s) at which `frame` started
};

/// What the sender did last; carried between clock_step() calls.
struct ClockState {
  bool have_last = false;
  int64_t last_frame = 0;
  double last_send = 0.0;
};

/// Result of one clock_step().
struct ClockDecision {
  bool send = false;   ///< send `frame` now
  int64_t frame = 0;   ///< frame count to send
  double next = 0.0;   ///< clock time (s) of the next step
};

/**
 * Decide whether to send a packet at time `now`, and when to look again.
 *
 * - Running (and anchor fresh): send each frame once, on its boundary
 *   (anchor.start + k * period). A frame at or up to two frames behind the
 *   last one sent is not re-sent, so a new anchor that lands slightly late
 *   never steps TC backwards.
 * - Paused: no repeats. The anchor frame is sent once if it differs from
 *   the last frame sent (e.g. a locate while stopped), then output goes
 *   quiet until TC moves again.
 * - Stale (running, but no fresh anchor for MAX_EXTRAPOLATION): silent.
 * - Invalid: send nothing.
 */
inline ClockDecision clock_step(const TcAnchor& a, ClockState& st, double now)
{
  ClockDecision d;
  if (!a.valid) {
    st.have_last = false;
    d.next = now + 0.1;
    return d;
  }

  const double period = tc_frame_period(a.type);
  const double age = now - a.start;

  if (a.running && age >= 0.0 && age < MAX_EXTRAPOLATION) {
    // Tiny bias so a wake-up a hair before the boundary counts as on it.
    const int64_t k = static_cast<int64_t>(std::floor(age / period + 1e-3));
    d.frame = a.frame + k;
    d.next = a.start + static_cast<double>(k + 1) * period;
    const int64_t behind = st.last_frame - d.frame;
    if (st.have_last && behind >= 0 && behind <= 2) return d;  // already sent
  } else {
    d.frame = a.frame;
    d.next = now + period;
    // Stale running anchor (script stalled): the anchor frame is older than
    // what was already extrapolated, so sending it would step back. Drop.
    if (a.running && st.have_last) return d;
    if (st.have_last && st.last_frame == a.frame) return d;  // held: drop
  }

  d.send = true;
  st.have_last = true;
  st.last_frame = d.frame;
  st.last_send = now;
  return d;
}

} // namespace reatc
