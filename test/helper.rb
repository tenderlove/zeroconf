ENV["MT_NO_PLUGINS"] = "1"

require "minitest/autorun"
require "zeroconf"

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

    def make_server iface
      Service.new SERVICE + ".",
        42424,
        HOST_NAME,
        service_interfaces: [iface], text: ["test=1", "other=value"]
    end

    def make_listener rd, q
      Thread.new do
        sock = open_ipv4 Addrinfo.new(Socket.sockaddr_in(Resolv::MDNS::Port, Socket::INADDR_ANY)), Resolv::MDNS::Port
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
