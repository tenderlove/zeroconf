# frozen_string_literal: true

require "zeroconf/client"

module ZeroConf
  class Browser < Client
    def browse timeout: 3, &blk
      sockets = open_interfaces 0

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
