ENV["MT_NO_PLUGINS"] = "1"

require "minitest/autorun"
require "zeroconf"

Thread.abort_on_exception = true

class NotParallel
  def self.start; end
  def self.shutdown; end
end

Minitest.parallel_executor = NotParallel

Thread.new do
  # this test suite shouldn't take any more than 60 seconds
  sleep 60

  Thread.list.each do |t|
    next if t == Thread.current
    puts "#" * 90
    p t
    puts t.backtrace
    puts "#" * 90
  end

  exit!
end

module ZeroConf
  class Test < Minitest::Test
    SERVICE = "_test-mdns._tcp.local"
    HOST_NAME = "tc-lan-adapter"
    SERVICE_NAME = "#{HOST_NAME}.#{SERVICE}"

    def time_it
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    end

    def make_server iface, host = HOST_NAME, **opts
      Service.new SERVICE + ".",
        42424,
        host,
        service_interfaces: [iface], text: ["test=1", "other=value"],
        **opts
    end

    def make_listener rd, q
      Thread.new do
        sock = open_ipv4 Addrinfo.new(Socket.sockaddr_in(Resolv::MDNS::Port, Socket::INADDR_ANY)), Resolv::MDNS::Port
        Thread.current[:started] = true
        loop do
          readers, = IO.select([sock, rd])
          read = readers.first
          if read == rd
            rd.close
            sock.close
            break
          end
          buf, = read.recvfrom 2048
          q << Resolv::DNS::Message.decode(buf)
        end
      end
    end
  end
end
