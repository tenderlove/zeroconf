# frozen_string_literal: true

require "zeroconf/client"

module ZeroConf
  class Discoverer < Client
    DISCOVER_QUERY = Resolv::DNS::Message.new 0
    DISCOVER_QUERY.add_question DISCOVERY_NAME, PTR

    def initialize interfaces: ZeroConf.interfaces
      super(nil, interfaces:)
    end

    def discover timeout: 3
      sockets = open_interfaces 0

      discover_query = DISCOVER_QUERY
      sockets.each { |socket| multicast_send(socket, discover_query.encode) }

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      now = start
      msgs = nil

      loop do
        readers, = IO.select(sockets, [], [], timeout && (timeout - (now - start)))
        return msgs unless readers
        readers.each do |reader|
          buf, _ = reader.recvfrom 2048
          msg = Resolv::DNS::Message.decode(buf)
          # only yield replies to this question
          if msg.question.length > 0 && msg.question.first.last == PTR
            if block_given?
              if :done == yield(msg)
                return msg
              end
            else
              msgs ||= []
              msgs << msg
            end
          end
        end
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    ensure
      sockets.each(&:close) if sockets
    end
  end
end
