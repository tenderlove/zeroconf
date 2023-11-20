require "socket"
require "ipaddr"
require "fcntl"
require "resolv"

module ZeroConf
  MDNS_UNICAST_RESPONSE = 0x8000

  class Query < Resolv::DNS::Resource::PTR
    ClassValue = 1 | MDNS_UNICAST_RESPONSE
  end

  def self.browse *names, interfaces: self.interfaces, timeout: 3, &blk
    # TODO: Fix IPV6
    port = 0
    sockets = interfaces.select { |ifa| ifa.addr.ipv4? }.map { |iface|
      if iface.addr.ipv4?
        open_ipv4 iface.addr, port
      else
        open_ipv6 iface.addr, port
      end
    }

    queries = names.map { |name| Query.new name }

    send_query queries, sockets, timeout, &blk
  ensure
    sockets.map(&:close)
  end

  def self.interfaces
    addrs = Socket.getifaddrs
    addrs.select { |ifa|
      ifa.addr &&
        (ifa.flags & Socket::IFF_UP > 0) &&         # must be up
        (ifa.flags & Socket::IFF_MULTICAST > 0) &&  # must have multicast
        (ifa.flags & Socket::IFF_LOOPBACK == 0) &&  # must not be loopback
        (ifa.flags & Socket::IFF_POINTOPOINT == 0)  # must not be pointopoint
    }
  end

  private_class_method def self.send_query queries, sockets, timeout
    sockets.each { |socket| multiquery_send socket, queries, 0 }

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    now = start

    loop do
      readers, = IO.select(sockets, [], [], timeout - (now - start))
      return unless readers
      readers.each do |reader|
        yield query_recv(reader)
      end
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  private_class_method def self.open_ipv4 saddr, port
    sock = UDPSocket.new Socket::AF_INET
    sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
    sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEPORT, true)
    sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_TTL, true)
    sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_LOOP, true)
    setup_ipv4 sock, saddr, port
    sock
  end

  private_class_method def self.setup_ipv4 sock, saddr, port
    sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP,
                    IPAddr.new(Resolv::MDNS::AddressV4).hton + IPAddr.new(saddr.ip_address).hton)
    sock.setsockopt(Socket::IPPROTO_IP, Socket::IP_MULTICAST_IF, IPAddr.new(saddr.ip_address).hton)
    sock.bind saddr.ip_address, port
    flags = sock.fcntl(Fcntl::F_GETFL, 0)
    sock.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK | flags)
  end

  private_class_method def self.multiquery_send sock, queries, query_id
    query = Resolv::DNS::Message.new query_id

    queries.each { |q| query.add_question q.name, q.class }

    multicast_send sock, query.encode
  end

  private_class_method def self.multicast_send sock, query
    dest = if sock.local_address.ipv4?
      Addrinfo.new Socket.sockaddr_in(Resolv::MDNS::Port, Resolv::MDNS::AddressV4)
    else
      raise NotImplementedError
    end
    sock.send(query, 0, dest)
  end

  private_class_method def self.query_recv sock
    buf, = sock.recvfrom 2048
    Resolv::DNS::Message.decode(buf)
  end
end
