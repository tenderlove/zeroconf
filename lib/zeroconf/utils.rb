# frozen_string_literal: true

require "socket"
require "ipaddr"
require "fcntl"
require "resolv"

module ZeroConf
  module Utils
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

    def multicast_send sock, query
      dest = if sock.local_address.ipv4?
        Addrinfo.new Socket.sockaddr_in(Resolv::MDNS::Port, Resolv::MDNS::AddressV4)
      else
        raise NotImplementedError
      end
      p sock.send(query, 0, dest)
    end
  end
end
