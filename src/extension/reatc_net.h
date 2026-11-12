/*
 * reatc_net.h — UDP sending and local interface discovery for ReaTC.
 *
 * Kept in its own translation unit: on Windows it needs <winsock2.h>, which
 * must not be mixed with the <windows.h> that reaper_plugin.h pulls in.
 *
 * Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
 */
#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace reatc {

/// Initialise the socket library (WSAStartup on Windows). Safe to call twice.
bool net_init();
/// Release the socket library.
void net_shutdown();

/**
 * List local, up, non-loopback IPv4 interfaces.
 * One row per address, tab-separated, newline-terminated:
 *   <ip>\t<iface>\t<broadcast or ->\t<netmask>\n
 * On Windows <iface> is the adapter's friendly name ("Wi-Fi 2"), UTF-8.
 */
std::string list_interfaces();

/**
 * One UDP socket with SO_BROADCAST, optionally bound to a local source IP.
 * The socket is (re)created lazily when the source IP changes; parsed
 * destinations are cached until the destination string changes.
 */
class UdpSender {
public:
  UdpSender() = default;
  ~UdpSender();
  UdpSender(const UdpSender&) = delete;
  UdpSender& operator=(const UdpSender&) = delete;

  /**
   * Send one datagram to every destination in `dests`
   * (one IPv4 or a comma-separated list) on `port`.
   * @param src_ip local IPv4 to bind to, or "" for the OS default route
   * @return datagrams sent (>= 1), or -1 on failure (see last_error())
   */
  int send(const std::string& dests, int port, const std::string& src_ip,
           const uint8_t* data, std::size_t len);

  /// After a failed send: the error. After a successful send: a bind
  /// warning (source IP could not be bound, default route used) or "".
  const std::string& last_error() const { return err_; }

  void close();

private:
  bool ensure_socket(const std::string& src_ip);
  bool parse_dests(const std::string& dests);

  intptr_t sock_ = -1;          // SOCKET on Windows, int fd elsewhere
  bool have_sock_ = false;
  std::string sock_src_;        // source IP the current socket was made for
  std::string err_;
  std::string bind_warn_;       // set when bind to sock_src_ failed
  std::string dests_str_;       // cache key for addrs_
  std::vector<uint32_t> addrs_; // destinations, network byte order
};

} // namespace reatc
