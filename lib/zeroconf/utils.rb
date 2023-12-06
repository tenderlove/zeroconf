# frozen_string_literal: true

require "socket"
require "ipaddr"
require "fcntl"
require "resolv"

module ZeroConf
  module Utils
    DISCOVERY_NAME = "_services._dns-sd._udp.local."

    def open_ipv4 saddr, port
      sock = UDPSocket.new Socket::AF_INET
      sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
      sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEPORT, true)
      sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_TTL, true)
      sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_LOOP, true)
      sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP,
                      IPAddr.new(Resolv::MDNS::AddressV4).hton + IPAddr.new(saddr.ip_address).hton)
      sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_IF, IPAddr.new(saddr.ip_address).hton)
      sock.bind saddr.ip_address, port
      flags = sock.fcntl(Fcntl::F_GETFL, 0)
      sock.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK | flags)
      sock
    end

    BROADCAST_V4 = Addrinfo.new Socket.sockaddr_in(Resolv::MDNS::Port, Resolv::MDNS::AddressV4)
    BROADCAST_V6 = Addrinfo.new Socket.sockaddr_in(Resolv::MDNS::Port, Resolv::MDNS::AddressV6)

    def multicast_send sock, query
      dest = if sock.local_address.ipv4?
        BROADCAST_V4
      else
        BROADCAST_V6
      end

      sock.send(query, 0, dest)
    end

    def unicast_send sock, data, to
      sock.send(data, 0, Addrinfo.new(to))
    end

    def open_ipv6 saddr, port
      sock = UDPSocket.new Socket::AF_INET6
      sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
      sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEPORT, true)
      sock.setsockopt(Socket::IPPROTO_IPV6, Socket::IPV6_MULTICAST_HOPS, true)
      sock.setsockopt(Socket::IPPROTO_IPV6, Socket::IPV6_MULTICAST_LOOP, true)

      # This address isn't correct, but giving it to IPAddr seems to result
      # in the right bytes back from hton.
      # See: https://github.com/ruby/ipaddr/issues/63
      s = IPAddr.new("ff02:0000:0000:0000:0000:00fb:0000:0000").hton
      sock.setsockopt(Socket::IPPROTO_IPV6, Socket::IPV6_JOIN_GROUP, s)
      sock.setsockopt(Socket::IPPROTO_IPV6, Socket::IPV6_MULTICAST_IF, IPAddr.new(saddr.ip_address).hton)
      sock.bind saddr.ip_address, port
      flags = sock.fcntl(Fcntl::F_GETFL, 0)
      sock.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK | flags)

      sock
    rescue SystemCallError
    end
  end
end
