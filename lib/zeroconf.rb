# frozen_string_literal: true

require "zeroconf/service"
require "zeroconf/browser"
require "zeroconf/resolver"
require "zeroconf/discoverer"

module ZeroConf
  #include Utils

  ##
  # ZeroConf.browse
  #
  # Call this method to find server information for a particular service.
  # For example, to find server information for servers advertising
  # `_elg._tcp.local`, do this:
  #
  #     ZeroConf.browse("_elg._tcp.local") { |r| p r }
  #
  # Yields info it finds to the provided block as it is received.
  # Pass a list of interfaces you want to use, or just use the default.
  # Also takes a timeout parameter to specify the length of the timeout.
  #
  # @param [Array<Socket::Ifaddr>] interfaces list of interfaces to query
  # @param [Numeric] timeout number of seconds before returning
  def self.browse name, interfaces: self.interfaces, timeout: 3, &blk
    browser = ZeroConf::Browser.new(name, interfaces:)
    browser.run(timeout:, &blk)
  end

  ###
  # Get a list tuples with host name and Addrinfo objects for a particular
  # service name.
  #
  # For example:
  #
  #     pp ZeroConf.find_addrinfos("_elg._tcp.local")
  #       # [["elgato-key-light-2d93.local", #<Addrinfo: 10.0.1.249:9123 (elgato-key-light-2d93.local)>],
  #       #  ["elgato-key-light-2d93.local", #<Addrinfo: [fe80::3e6a:9dff:fe19:b313]:9123 (elgato-key-light-2d93.local)>],
  #       #  ["elgato-key-light-48c6.local", #<Addrinfo: 10.0.1.151:9123 (elgato-key-light-48c6.local)>],
  #       #  ["elgato-key-light-48c6.local", #<Addrinfo: [fe80::3e6a:9dff:fe19:3a99]:9123 (elgato-key-light-48c6.local)>]]
  #
  def self.find_addrinfos name, interfaces: self.interfaces, timeout: 3
    browse(name, interfaces:, timeout:).flat_map { |r|
      host = nil
      port = nil
      ipv4 = []
      ipv6 = []
      r.additional.each { |name, ttl, data|
        case data
        when Resolv::DNS::Resource::IN::SRV
          host = data.target.to_s
          port = data.port
        when Resolv::DNS::Resource::IN::A
          ipv4 << data.address
        when Resolv::DNS::Resource::IN::AAAA
          ipv6 << data.address
        end
      }
      ipv4.map { |x| [host, ["AF_INET", port, host, x.to_s]] } +
        ipv6.map { |x| [host, ["AF_INET6", port, host, x.to_s]] }
    }.uniq.map { |host, x| [host, Addrinfo.new(x)] }
  end

  def self.resolve name, interfaces: self.interfaces, timeout: 3, &blk
    resolver = ZeroConf::Resolver.new(name, interfaces:)
    resolver.run(timeout:, &blk)
  end

  def self.service service, service_port, hostname = Socket.gethostname, service_interfaces: self.service_interfaces, text: [""], ignore_malformed_requests: false
    s = Service.new(service, service_port, hostname, service_interfaces:, text:, ignore_malformed_requests:)
    s.start
  end

  ##
  # ZeroConf.find_services
  #
  # Get a list of services being advertised on the network!
  #
  # This method will yield the services as it finds them, or it will
  # return a list of unique service names if no block is given.
  #
  # @param [Array<Socket::Ifaddr>] interfaces list of interfaces to query
  # @param [Numeric] timeout number of seconds before returning
  def self.find_services interfaces: self.interfaces, timeout: 3
    if block_given?
      discover(interfaces:, timeout:) do |res|
        res.answer.map(&:last).map(&:name).map(&:to_s).each { yield _1 }
      end
    else
      discover(interfaces:, timeout:)
        .flat_map(&:answer)
        .map(&:last)
        .map(&:name)
        .map(&:to_s)
        .uniq
    end
  end

  ##
  # ZeroConf.discover
  #
  # Call this method to discover services on your network!
  # Yields services it finds to the provided block as it finds them.
  # Pass a list of interfaces you want to use, or just use the default.
  # Also takes a timeout parameter to specify the length of the timeout.
  #
  # @param [Array<Socket::Ifaddr>] interfaces list of interfaces to query
  # @param [Numeric] timeout number of seconds before returning
  def self.discover interfaces: self.interfaces, timeout: 3, &blk
    discoverer = ZeroConf::Discoverer.new(interfaces:)
    discoverer.run(timeout:, &blk)
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
end
