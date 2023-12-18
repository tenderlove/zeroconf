# frozen_string_literal: true

require "zeroconf/client"

module ZeroConf
  class Resolver < Client
    def resolve timeout: 3, &blk
      sockets = open_interfaces 0
      query = Resolv::DNS::Message.new 0
      query.add_question Resolv::DNS::Name.create(name), A

      sockets.each do |sock|
        multicast_send sock, query.encode
      end

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
    ensure
      sockets.map(&:close) if sockets
    end
  end
end
