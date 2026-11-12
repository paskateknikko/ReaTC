/*
 * reatc_output.h — frame-accurate Art-Net / OSC timecode sender.
 *
 * A background thread owns both UDP sockets and sends one packet per frame,
 * timed by the frame clock in reatc_clock.h. The Lua script only updates the
 * TC anchor and the output settings (main thread); all methods are
 * thread-safe.
 *
 * Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
 */
#pragma once

#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>

#include "reatc_clock.h"

namespace reatc {

/// Which output a status query is about.
enum class OutputKind { ArtNet, Osc };

class OutputSender {
public:
  OutputSender() = default;
  ~OutputSender() { stop(); }
  OutputSender(const OutputSender&) = delete;
  OutputSender& operator=(const OutputSender&) = delete;

  /// Start the sender thread (no-op if running).
  void start();
  /// Stop and join the sender thread, closing its sockets.
  void stop();

  /**
   * Update the TC the outputs follow. Called every script defer cycle;
   * if no update arrives for STALE_AFTER seconds, sending stops (script
   * closed or crashed).
   * @param age seconds since the current frame started (0 if unknown)
   */
  void set_tc(bool valid, int h, int m, int s, int f, int type, bool running,
              double age);

  /// Art-Net settings. `dests` is one IPv4 or a comma-separated list.
  void set_artnet(bool enabled, const std::string& dests,
                  const std::string& src_ip, int stream_id);

  /// OSC settings. `address` must start with '/'.
  void set_osc(bool enabled, const std::string& dest, int port,
               const std::string& address, const std::string& src_ip);

  /// Successful sends since the output was last enabled.
  int packets(OutputKind kind);
  /// Error from the most recent send, or "" if it succeeded.
  std::string last_error(OutputKind kind);
  /// Bind warning from the most recent successful send, or "".
  std::string last_warning(OutputKind kind);

  /// Seconds without set_tc() after which output stops.
  static constexpr double STALE_AFTER = 1.0;

private:
  struct Status {
    int packets = 0;
    std::string error;
    std::string warning;
  };
  struct ArtNetCfg {
    bool enabled = false;
    std::string dests, src_ip;
    int stream_id = 0;
  };
  struct OscCfg {
    bool enabled = false;
    std::string dest, address, src_ip;
    int port = 0;
  };

  void run();
  Status& status(OutputKind kind) { return kind == OutputKind::Osc ? osc_st_ : art_st_; }

  std::mutex mu_;
  std::condition_variable cv_;
  std::thread thread_;
  bool quit_ = false;

  // Guarded by mu_
  TcAnchor anchor_;
  double last_update_ = -1e9;
  ArtNetCfg art_;
  OscCfg osc_;
  Status art_st_, osc_st_;
};

/// Monotonic clock in seconds (the frame clock's time base).
double clock_now();

} // namespace reatc
