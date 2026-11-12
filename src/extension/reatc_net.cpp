/*
 * reatc_net.cpp — UDP sending and local interface discovery for ReaTC.
 *
 * Copyright (c) 2025 Tuukka Aimasmäki. MIT License — see LICENSE.
 */
#include "reatc_net.h"

#ifdef _WIN32
  #ifndef WIN32_LEAN_AND_MEAN
    #define WIN32_LEAN_AND_MEAN
  #endif
  #include <winsock2.h>
  #include <ws2tcpip.h>
  #include <iphlpapi.h>
  #include <windows.h>
  #pragma comment(lib, "ws2_32.lib")
  #pragma comment(lib, "iphlpapi.lib")
  typedef SOCKET sock_t;
  static const sock_t BAD_SOCK = INVALID_SOCKET;
  static int last_sock_error() { return WSAGetLastError(); }
  static void close_sock(sock_t s) { closesocket(s); }
#else
  #include <arpa/inet.h>
  #include <cerrno>
  #include <cstring>
  #include <ifaddrs.h>
  #include <net/if.h>
  #include <netinet/in.h>
  #include <sys/socket.h>
  #include <unistd.h>
  typedef int sock_t;
  static const sock_t BAD_SOCK = -1;
  static int last_sock_error() { return errno; }
  static void close_sock(sock_t s) { ::close(s); }
#endif

#include <cstdio>

namespace reatc {

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

static std::string ipv4_str(uint32_t net_order)
{
  in_addr a;
  a.s_addr = net_order;
  char buf[INET_ADDRSTRLEN] = {};
  inet_ntop(AF_INET, &a, buf, sizeof(buf));
  return buf;
}

static bool parse_ipv4(const std::string& s, uint32_t& out_net_order)
{
  in_addr a;
  if (inet_pton(AF_INET, s.c_str(), &a) != 1) return false;
  out_net_order = a.s_addr;
  return true;
}

static std::string trim(const std::string& s)
{
  const char* ws = " \t\r\n";
  const auto b = s.find_first_not_of(ws);
  if (b == std::string::npos) return "";
  const auto e = s.find_last_not_of(ws);
  return s.substr(b, e - b + 1);
}

static std::string sock_error_text(const char* what, int code)
{
  char buf[160];
  std::snprintf(buf, sizeof(buf), "%s failed (error %d)", what, code);
  return buf;
}

/// Append one interface row; broadcast is derived from ip/mask ("-" for /32).
static void append_row(std::string& out, uint32_t ip_net, uint32_t mask_net,
                       const std::string& name)
{
  const uint32_t ip = ntohl(ip_net);
  if ((ip >> 24) == 127) return;  // loopback
  const uint32_t mask = ntohl(mask_net);
  std::string bcast = "-";
  if (mask != 0xFFFFFFFFu) bcast = ipv4_str(htonl(ip | ~mask));
  out += ipv4_str(ip_net);
  out += '\t';
  out += name.empty() ? std::string("?") : name;
  out += '\t';
  out += bcast;
  out += '\t';
  out += ipv4_str(mask_net);
  out += '\n';
}

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

#ifdef _WIN32
static bool g_wsa_ok = false;
#endif

bool net_init()
{
#ifdef _WIN32
  if (g_wsa_ok) return true;
  WSADATA wsa;
  g_wsa_ok = (WSAStartup(MAKEWORD(2, 2), &wsa) == 0);
  return g_wsa_ok;
#else
  return true;
#endif
}

void net_shutdown()
{
#ifdef _WIN32
  if (g_wsa_ok) { WSACleanup(); g_wsa_ok = false; }
#endif
}

// ---------------------------------------------------------------------------
// Interface discovery
// ---------------------------------------------------------------------------

#ifdef _WIN32

static std::string wide_to_utf8(const wchar_t* w)
{
  if (!w || !*w) return "";
  const int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, nullptr, 0, nullptr, nullptr);
  if (n <= 1) return "";
  std::string s(static_cast<size_t>(n - 1), '\0');
  WideCharToMultiByte(CP_UTF8, 0, w, -1, &s[0], n, nullptr, nullptr);
  return s;
}

std::string list_interfaces()
{
  std::string out;
  const ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST |
                      GAA_FLAG_SKIP_DNS_SERVER;
  ULONG size = 16 * 1024;
  std::vector<unsigned char> buf;
  ULONG ret = ERROR_BUFFER_OVERFLOW;
  for (int attempt = 0; attempt < 3 && ret == ERROR_BUFFER_OVERFLOW; ++attempt) {
    buf.resize(size);
    ret = GetAdaptersAddresses(AF_INET, flags, nullptr,
                               reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buf.data()),
                               &size);
  }
  if (ret != NO_ERROR) return out;

  for (auto* ad = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buf.data()); ad;
       ad = ad->Next) {
    if (ad->OperStatus != IfOperStatusUp) continue;
    if (ad->IfType == IF_TYPE_SOFTWARE_LOOPBACK) continue;
    const std::string name = wide_to_utf8(ad->FriendlyName);
    for (auto* ua = ad->FirstUnicastAddress; ua; ua = ua->Next) {
      const sockaddr* sa = ua->Address.lpSockaddr;
      if (!sa || sa->sa_family != AF_INET) continue;
      const uint32_t ip = reinterpret_cast<const sockaddr_in*>(sa)->sin_addr.s_addr;
      const unsigned prefix = ua->OnLinkPrefixLength;
      const uint32_t mask = prefix == 0 ? 0u
                          : prefix >= 32 ? 0xFFFFFFFFu
                          : (0xFFFFFFFFu << (32 - prefix));
      append_row(out, ip, htonl(mask), name);
    }
  }
  return out;
}

#else

std::string list_interfaces()
{
  std::string out;
  ifaddrs* list = nullptr;
  if (getifaddrs(&list) != 0) return out;
  for (ifaddrs* it = list; it; it = it->ifa_next) {
    if (!it->ifa_addr || it->ifa_addr->sa_family != AF_INET) continue;
    if (!(it->ifa_flags & IFF_UP) || (it->ifa_flags & IFF_LOOPBACK)) continue;
    const uint32_t ip = reinterpret_cast<sockaddr_in*>(it->ifa_addr)->sin_addr.s_addr;
    const uint32_t mask = it->ifa_netmask
        ? reinterpret_cast<sockaddr_in*>(it->ifa_netmask)->sin_addr.s_addr
        : 0xFFFFFFFFu;
    append_row(out, ip, mask, it->ifa_name ? it->ifa_name : "");
  }
  freeifaddrs(list);
  return out;
}

#endif

// ---------------------------------------------------------------------------
// UdpSender
// ---------------------------------------------------------------------------

UdpSender::~UdpSender() { close(); }

void UdpSender::close()
{
  if (have_sock_) {
    close_sock(static_cast<sock_t>(sock_));
    have_sock_ = false;
    sock_ = -1;
  }
  sock_src_.clear();
}

bool UdpSender::ensure_socket(const std::string& src_ip)
{
  if (have_sock_ && src_ip == sock_src_) return true;
  close();

  if (!net_init()) { err_ = "socket library init failed"; return false; }

  const sock_t s = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if (s == BAD_SOCK) {
    err_ = sock_error_text("socket()", last_sock_error());
    return false;
  }
  int yes = 1;
  setsockopt(s, SOL_SOCKET, SO_BROADCAST,
             reinterpret_cast<const char*>(&yes), sizeof(yes));

  bind_warn_.clear();
  if (!src_ip.empty()) {
    sockaddr_in local = {};
    local.sin_family = AF_INET;
    local.sin_port = 0;
    uint32_t a = 0;
    if (!parse_ipv4(src_ip, a)) {
      bind_warn_ = "invalid source IP " + src_ip + " (using default route)";
    } else {
      local.sin_addr.s_addr = a;
      if (bind(s, reinterpret_cast<sockaddr*>(&local), sizeof(local)) != 0) {
        // Same as the old Python daemons: keep going unbound.
        bind_warn_ = sock_error_text(("bind " + src_ip).c_str(), last_sock_error()) +
                     " (using default route)";
      }
    }
  }

  sock_ = static_cast<intptr_t>(s);
  have_sock_ = true;
  sock_src_ = src_ip;
  return true;
}

bool UdpSender::parse_dests(const std::string& dests)
{
  if (dests == dests_str_ && !addrs_.empty()) return true;
  addrs_.clear();
  dests_str_ = dests;
  size_t start = 0;
  while (start <= dests.size()) {
    size_t comma = dests.find(',', start);
    if (comma == std::string::npos) comma = dests.size();
    const std::string item = trim(dests.substr(start, comma - start));
    if (!item.empty()) {
      uint32_t a = 0;
      if (!parse_ipv4(item, a)) {
        addrs_.clear();
        err_ = "invalid destination IP: " + item;
        return false;
      }
      addrs_.push_back(a);
    }
    start = comma + 1;
  }
  if (addrs_.empty()) { err_ = "no destination IP"; return false; }
  return true;
}

int UdpSender::send(const std::string& dests, int port,
                    const std::string& src_ip, const uint8_t* data,
                    std::size_t len)
{
  if (port < 1 || port > 65535) { err_ = "invalid port"; return -1; }
  if (!parse_dests(dests)) return -1;
  if (!ensure_socket(src_ip)) return -1;

  const sock_t s = static_cast<sock_t>(sock_);
  int sent = 0;
  int last_err = 0;
  for (uint32_t a : addrs_) {
    sockaddr_in to = {};
    to.sin_family = AF_INET;
    to.sin_port = htons(static_cast<uint16_t>(port));
    to.sin_addr.s_addr = a;
    const auto r = sendto(s, reinterpret_cast<const char*>(data),
                          static_cast<int>(len), 0,
                          reinterpret_cast<const sockaddr*>(&to), sizeof(to));
    if (r >= 0) ++sent;
    else last_err = last_sock_error();
  }
  if (sent == 0) {
    err_ = sock_error_text("sendto", last_err);
    // Network may have changed (adapter down, IP gone): rebuild next time.
    close();
    return -1;
  }
  err_ = bind_warn_;  // success: only a bind warning (if any) remains
  return sent;
}

} // namespace reatc
