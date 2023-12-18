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
      sockets = open_interfaces 0

      query = get_query
      sockets.each { |socket| multicast_send(socket, query.encode) }

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      now = start
      msgs = block_given? ? nil : []

      loop do
        readers, = IO.select(sockets, [], [], timeout && (timeout - (now - start)))
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
