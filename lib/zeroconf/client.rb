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

    def run timeout: 3
      sockets = open_interfaces interfaces.map(&:addr), Resolv::MDNS::Port

      query = get_query
      sockets.each { |socket| multicast_send(socket, query.encode) }

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      now = start
      msgs = block_given? ? nil : []

      loop do
        wait = timeout && timeout - (now - start)
        return if wait && wait < 0

        readers, = IO.select(sockets, [], [], wait)

        return msgs unless readers

        readers.each do |reader|
          buf, _ = reader.recvfrom 2048
          msg = Resolv::DNS::Message.decode(buf)
          # only yield replies to this question
          if interested? msg
            if block_given?
              if :done == yield(msg)
                return msg
              end
            else
              msgs << msg
            end
          end
        end
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    ensure
      sockets.each(&:close) if sockets
    end

    private

    def interested? _; true; end

    def open_interfaces addrs, port
      addrs.map { |addr|
        if addr.ipv4?
          open_ipv4 addr, port
        else
          open_ipv6 addr, port
        end
      }.compact
    end
  end
end
