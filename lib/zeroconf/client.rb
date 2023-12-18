# frozen_string_literal: true

require "zeroconf/utils"

module ZeroConf
  class Client
    include Utils

    attr_reader :name, :interfaces

    def initialize name, interfaces: ZeroConf.interfaces
      @name = name
      @interfaces = interfaces
    end

    private

    def open_interfaces port
      interfaces.map { |iface|
        if iface.addr.ipv4?
          open_ipv4 iface.addr, port
        else
          open_ipv6 iface.addr, port
        end
      }.compact
    end
  end
end
