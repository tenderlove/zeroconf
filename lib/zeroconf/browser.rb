# frozen_string_literal: true

require "zeroconf/utils"

module ZeroConf
  class Browser
    include Utils

    attr_reader :name, :interfaces

    def initialize name, interfaces: ZeroConf.interfaces
      @name = name
      @interfaces = interfaces
    end

    def browse timeout: 3, &blk
      port = 0
      sockets = interfaces.map { |iface|
        if iface.addr.ipv4?
          open_ipv4 iface.addr, port
        else
          open_ipv6 iface.addr, port
        end
      }.compact

      q = PTR.new(name)

      sockets.each { |socket|
        query = Resolv::DNS::Message.new 0

        query.add_question q.name, q.class

        multicast_send socket, query.encode
      }

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      now = start
      msgs = block_given? ? nil : []

      loop do
        readers, = IO.select(sockets, [], [], timeout - (now - start))
        return msgs unless readers
        readers.each do |reader|
          buf, = reader.recvfrom 2048
          msg = Resolv::DNS::Message.decode(buf)
          if block_given?
            return msg if :done == yield(msg)
          else
            msgs << msg
          end
        end
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    ensure
      sockets.map(&:close) if sockets
    end
  end
end
