/*
 * reatc_output.cpp — frame-accurate Art-Net / OSC timecode sender thread.
 *
 * Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
 */
#include "reatc_output.h"

#include <chrono>
#include <vector>

#include "reatc_net.h"
#include "reatc_packets.h"

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>  // timeBeginPeriod: 1 ms sleep granularity
#endif

namespace reatc {

/// Wake this long after a frame boundary, so a slightly early wake-up
/// doesn't land just before it.
static constexpr double WAKE_MARGIN = 0.0002;
/// Waits longer than this only cover APPROACH_FRACTION of the remaining time.
static constexpr double APPROACH_BELOW = 0.002;
static constexpr double APPROACH_FRACTION = 0.8;

double clock_now()
{
  using namespace std::chrono;
  return duration<double>(steady_clock::now().time_since_epoch()).count();
}

void OutputSender::start()
{
  std::lock_guard<std::mutex> lk(mu_);
  if (thread_.joinable()) return;
  quit_ = false;
  thread_ = std::thread([this] { run(); });
}

void OutputSender::stop()
{
  {
    std::lock_guard<std::mutex> lk(mu_);
    if (!thread_.joinable()) return;
    quit_ = true;
  }
  cv_.notify_all();
  thread_.join();
}

void OutputSender::set_tc(bool valid, int h, int m, int s, int f, int type,
                          bool running, double age)
{
  valid = valid && tc_in_range(h, m, s, f, type);
  const double now = clock_now();
  bool wake;
  {
    std::lock_guard<std::mutex> lk(mu_);
    TcAnchor a;
    a.valid = valid;
    a.running = valid && running;
    a.type = type;
    a.frame = valid ? tc_to_frames(h, m, s, f, type) : 0;
    a.start = now - (age > 0.0 ? age : 0.0);
    // Wake the sender on state changes and jumps; within a running stream
    // it already wakes on the next frame boundary.
    wake = a.valid != anchor_.valid || a.running != anchor_.running ||
           a.type != anchor_.type || now - last_update_ > STALE_AFTER ||
           (a.frame != anchor_.frame && !a.running);
    anchor_ = a;
    last_update_ = now;
  }
  if (wake) cv_.notify_all();
}

void OutputSender::set_artnet(bool enabled, const std::string& dests,
                              const std::string& src_ip, int stream_id)
{
  bool wake;
  {
    std::lock_guard<std::mutex> lk(mu_);
    wake = enabled != art_.enabled;
    if (enabled && !art_.enabled) art_st_ = Status();
    art_ = ArtNetCfg{ enabled, dests, src_ip, stream_id };
  }
  if (wake) cv_.notify_all();
}

void OutputSender::set_osc(bool enabled, const std::string& dest, int port,
                           const std::string& address, const std::string& src_ip)
{
  bool wake;
  {
    std::lock_guard<std::mutex> lk(mu_);
    wake = enabled != osc_.enabled;
    if (enabled && !osc_.enabled) osc_st_ = Status();
    osc_ = OscCfg{ enabled, dest, address, src_ip, port };
  }
  if (wake) cv_.notify_all();
}

int OutputSender::packets(OutputKind kind)
{
  std::lock_guard<std::mutex> lk(mu_);
  return status(kind).packets;
}

std::string OutputSender::last_error(OutputKind kind)
{
  std::lock_guard<std::mutex> lk(mu_);
  return status(kind).error;
}

std::string OutputSender::last_warning(OutputKind kind)
{
  std::lock_guard<std::mutex> lk(mu_);
  return status(kind).warning;
}

void OutputSender::run()
{
#ifdef _WIN32
  timeBeginPeriod(1);
#endif
  UdpSender art_sock, osc_sock;  // only touched by this thread
  ClockState clock;

  std::unique_lock<std::mutex> lk(mu_);
  while (!quit_) {
    const double now = clock_now();
    TcAnchor a = anchor_;
    if (now - last_update_ > STALE_AFTER) a.valid = false;
    if (!art_.enabled && !osc_.enabled) a.valid = false;

    const ClockDecision d = clock_step(a, clock, now);
    if (d.send) {
      const ArtNetCfg art = art_;
      const OscCfg osc = osc_;
      int h, m, s, f;
      frames_to_tc(d.frame, a.type, h, m, s, f);
      lk.unlock();

      int art_ret = 0, osc_ret = 0;
      std::string osc_err;
      if (art.enabled) {
        uint8_t pkt[ARTNET_TC_LEN];
        build_artnet_timecode(pkt, h, m, s, f, a.type, art.stream_id);
        art_ret = art_sock.send(art.dests, ARTNET_PORT, art.src_ip, pkt, sizeof(pkt));
      }
      if (osc.enabled) {
        if (osc.address.empty() || osc.address[0] != '/') {
          osc_ret = -1;
          osc_err = "OSC address must start with /";
        } else {
          const auto pkt = build_osc_timecode(osc.address, h, m, s, f, a.type);
          osc_ret = osc_sock.send(osc.dest, osc.port, osc.src_ip, pkt.data(), pkt.size());
          if (osc_ret < 0) osc_err = osc_sock.last_error();
        }
      }

      lk.lock();
      // Skip outputs disabled while we were sending (their status is moot).
      if (art.enabled && art_.enabled) {
        if (art_ret > 0) {
          ++art_st_.packets;
          art_st_.error.clear();
          art_st_.warning = art_sock.last_error();
        } else {
          art_st_.error = art_sock.last_error();
        }
      }
      if (osc.enabled && osc_.enabled) {
        if (osc_ret > 0) {
          ++osc_st_.packets;
          osc_st_.error.clear();
          osc_st_.warning = osc_sock.last_error();
        } else {
          osc_st_.error = osc_err;
        }
      }
      if (quit_) break;
    }

    // Sleep until just past the next frame boundary, or until a settings /
    // state change. OS timers wake late by a fraction of the interval
    // (macOS timer coalescing: ~10%, i.e. ~4 ms on a 40 ms wait), so long
    // waits cover only part of the remaining time and the loop re-checks;
    // the last, short wait lands within a fraction of a millisecond.
    double wait = d.next - clock_now() + WAKE_MARGIN;
    if (wait > APPROACH_BELOW) wait *= APPROACH_FRACTION;
    if (wait > 0.25) wait = 0.25;  // stale / disabled checks still run
    if (wait > 0.0)
      cv_.wait_for(lk, std::chrono::microseconds(static_cast<long long>(wait * 1e6)));
  }
  lk.unlock();

  art_sock.close();
  osc_sock.close();
#ifdef _WIN32
  timeEndPeriod(1);
#endif
}

} // namespace reatc
