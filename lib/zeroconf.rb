# frozen_string_literal: true

require "zeroconf/utils"
require "zeroconf/service"

module ZeroConf
  MDNS_CACHE_FLUSH = 0x8000

  extend Utils
  include Utils

  # :stopdoc:
  class PTR < Resolv::DNS::Resource::IN::PTR
    MDNS_UNICAST_RESPONSE = 0x8000

    ClassValue = Resolv::DNS::Resource::IN::ClassValue | MDNS_UNICAST_RESPONSE
    ClassHash[[TypeValue, ClassValue]] = self # :nodoc:
  end

  class ANY < Resolv::DNS::Resource::IN::ANY
    MDNS_UNICAST_RESPONSE = 0x8000

    ClassValue = Resolv::DNS::Resource::IN::ClassValue | MDNS_UNICAST_RESPONSE
    ::Resolv::DNS::Resource::ClassHash[[TypeValue, ClassValue]] = self # :nodoc:
  end

  class A < Resolv::DNS::Resource::IN::A
    MDNS_UNICAST_RESPONSE = 0x8000

    ClassValue = Resolv::DNS::Resource::IN::ClassValue | MDNS_UNICAST_RESPONSE
    ClassHash[[TypeValue, ClassValue]] = self # :nodoc:
  end

  class SRV < Resolv::DNS::Resource::IN::SRV
    MDNS_UNICAST_RESPONSE = 0x8000

    ClassValue = Resolv::DNS::Resource::IN::ClassValue | MDNS_UNICAST_RESPONSE
    ClassHash[[TypeValue, ClassValue]] = self # :nodoc:
  end

  module MDNS
    module Announce
      module IN
        [:SRV, :A, :AAAA, :TXT].each do |name|
          const_set(name, Class.new(Resolv::DNS::Resource::IN.const_get(name)) {
            const_set(:ClassValue, superclass::ClassValue | MDNS_CACHE_FLUSH)
            self::ClassHash[[self::TypeValue, self::ClassValue]] = self
          })
        end
      end
    end
  end

  # :startdoc:

  DISCOVER_QUERY = Resolv::DNS::Message.new 0
  DISCOVER_QUERY.add_question DISCOVERY_NAME, PTR

  def self.browse *names, interfaces: self.interfaces, timeout: 3, &blk
    port = 0
    sockets = interfaces.map { |iface|
      if iface.addr.ipv4?
        open_ipv4 iface.addr, port
      else
        open_ipv6 iface.addr, port
      end
    }.compact

    queries = names.map { |name| PTR.new name }

    send_query queries, sockets, timeout, &blk
  ensure
    sockets.map(&:close) if sockets
  end

  def self.lookup *names, interfaces: self.interfaces, timeout: 3, &blk
    # TODO: Fix IPV6
    port = 0
    sockets = interfaces.map { |iface|
      if iface.addr.ipv4?
        open_ipv4 iface.addr, port
      else
        open_ipv6 iface.addr, port
      end
    }.compact

    queries = names.map { |name| A.new name }

    send_query queries, sockets, timeout, &blk
  ensure
    sockets.map(&:close) if sockets
  end

  def self.service service, service_port, hostname = Socket.gethostname, service_interfaces: self.service_interfaces, text: [""]
    s = Service.new(service, service_port, hostname, service_interfaces:, text:)
    s.start
  end

  def self.discover interfaces: self.interfaces, timeout: 3
    port = 0

    sockets = interfaces.map { |iface|
      if iface.addr.ipv4?
        open_ipv4 iface.addr, port
      else
        open_ipv6 iface.addr, port
      end
    }.compact

    discover_query = DISCOVER_QUERY
    sockets.each { |socket| multicast_send(socket, discover_query.encode) }

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    now = start

    loop do
      readers, = IO.select(sockets, [], [], timeout && (timeout - (now - start)))
      return unless readers
      readers.each do |reader|
        buf, _ = reader.recvfrom 2048
        msg = Resolv::DNS::Message.decode(buf)
        # only yield replies to this question
        if msg.question.length > 0 && msg.question.first.last == PTR
          if :done == yield(msg)
            return msg
          end
        end
      end
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  ensure
    sockets.each(&:close) if sockets
  end

  def self.interfaces
    addrs = Socket.getifaddrs
    addrs.select { |ifa|
      addr = ifa.addr
      addr &&
        (ifa.flags & Socket::IFF_UP > 0) &&            # must be up
        (ifa.flags & Socket::IFF_MULTICAST > 0) &&     # must have multicast
        (ifa.flags & Socket::IFF_POINTOPOINT == 0) &&  # must not be pointopoint
        (ifa.flags & Socket::IFF_LOOPBACK == 0) &&     # must not be loopback
        (addr.ipv4? ||                                 # must be ipv4 *or*
         (addr.ipv6? && !addr.ipv6_linklocal?))        # must be ipv6 and not link local
    }
  end

  def self.service_interfaces
    ipv4, ipv6 = interfaces.partition { |ifa| ifa.addr.ipv4? }
    [ipv4.first, ipv6&.first].compact
  end

  private_class_method def self.send_query queries, sockets, timeout
    sockets.each { |socket| multiquery_send socket, queries, 0 }

    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    now = start

    loop do
      readers, = IO.select(sockets, [], [], timeout - (now - start))
      return unless readers
      readers.each do |reader|
        buf, = reader.recvfrom 2048
        msg = Resolv::DNS::Message.decode(buf)
        return msg if :done == yield(msg)
      end
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end

  private_class_method def self.multiquery_send sock, queries, query_id
    query = Resolv::DNS::Message.new query_id

    queries.each { |q| query.add_question q.name, q.class }

    multicast_send sock, query.encode
  end
end
