require "helper"

module ZeroConf
  class ServiceTest < Test
    include ZeroConf::Utils

    attr_reader :iface

    def setup
      super
      @iface = ZeroConf.interfaces.find_all { |x| x.addr.ipv4? }.first
    end

    def test_service_info
      s = Service.new "_test-mdns._tcp.local.",
        42424,
        "tc-lan-adapter",
        service_interfaces: [iface]

      assert_equal "_test-mdns._tcp.local.", s.service
      assert_equal 42424, s.service_port
      assert_equal "tc-lan-adapter", s.hostname
      assert_equal [iface], s.service_interfaces
      assert_equal "#{s.hostname}.#{s.service}", s.service_name
      assert_equal "#{s.hostname}.local.", s.qualified_host
      assert_equal [""], s.text
    end

    def test_unicast_service_instance_answer
      s = make_server iface
      runner = Thread.new { s.start }

      query = Resolv::DNS::Message.new 0
      query.add_question "tc-lan-adapter._test-mdns._tcp.local.", ZeroConf::SRV

      sock = open_ipv4 iface.addr, 0
      multicast_send sock, query.encode
      res = Resolv::DNS::Message.decode sock.recvfrom(2048).first
      s.stop
      runner.join

      expected = Resolv::DNS::Message.new(0)
      expected.qr = 1
      expected.aa = 1

      expected.add_additional s.qualified_host,
        10,
        Resolv::DNS::Resource::IN::A.new(iface.addr.ip_address)

      expected.add_additional s.service_name,
        10,
        Resolv::DNS::Resource::IN::TXT.new(*s.text)
      expected.add_answer s.service_name, 10, Resolv::DNS::Resource::IN::SRV.new(0, 0, s.service_port, s.qualified_host)
      expected.add_question s.service_name, ZeroConf::MDNS::Announce::IN::SRV

      assert_equal expected, res
    end

    def test_multicast_discover
      q = Queue.new
      rd, wr = IO.pipe

      listen = make_listener rd, q
      s = make_server iface
      server = Thread.new { s.start }

      query = Resolv::DNS::Message.new 0
      query.add_question "_services._dns-sd._udp.local.", Resolv::DNS::Resource::IN::PTR
      sock = open_ipv4 iface.addr, 0
      multicast_send sock, query.encode

      while res = q.pop
        if res.answer.find { |name, ttl, data| name.to_s == "_services._dns-sd._udp.local" && data.name.to_s == "_test-mdns._tcp.local" }
          wr.write "x"
          break
        end
      end

      listen.join
      s.stop
      server.join

      msg = Resolv::DNS::Message.new(0)
      msg.qr = 1
      msg.aa = 1

      msg.add_answer DISCOVERY_NAME, 60,
        Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(s.service))
      msg

      assert_equal msg, res
    end

    def test_announcement
      ann = "\x00\x00\x84\x00\x00\x00\x00\x01\x00\x00\x00\x03\n_test-mdns\x04_tcp\x05local\x00\x00\f\x00\x01\x00\x00\x00<\x00\x15\x0Etc-lan-adapter\x03lan\xC0\f\xC0-\x00!\x80\x01\x00\x00\x00<\x00 \x00\x00\x00\x00\xA5\xB8\x0Etc-lan-adapter\x03lan\x05local\x00\xC0T\x00\x01\x80\x01\x00\x00\x00<\x00\x04\n\x00\x01\x95\xC0T\x00\x1C\x80\x01\x00\x00\x00<\x00\x10\xFD\xDA\x85k\tL\x00\x00\x10\xF6\x892\xEA\xBB\\H".b
      msg = Resolv::DNS::Message.decode ann
      service = Service.new "_test-mdns._tcp.local.", 42424
      assert_equal msg.encode, service.announcement.encode
    end

    def test_dnssd_unicast_answer
      s = make_server iface
      runner = Thread.new { s.start }

      query = Resolv::DNS::Message.new 0
      query.add_question "_services._dns-sd._udp.local.", ZeroConf::PTR

      sock = open_ipv4 iface.addr, 0
      multicast_send sock, query.encode

      res = nil
      loop do
        buf, from = sock.recvfrom(2048)
        res = Resolv::DNS::Message.decode buf
        if from.last == iface.addr.ip_address
          break if res.answer.find { |name, ttl, data| data.name.to_s == "_test-mdns._tcp.local" }
        end
      end

      s.stop
      runner.join

      expected = Resolv::DNS::Message.new(0)
      expected.qr = 1
      expected.aa = 1

      expected.add_answer ZeroConf::Service::MDNS_NAME, 10,
        Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(s.service))

      expected.add_question ZeroConf::Service::MDNS_NAME, ZeroConf::PTR

      assert_equal expected, res
    end

    def test_service_multicast_answer
      q = Queue.new
      rd, wr = IO.pipe

      listen = make_listener rd, q
      s = make_server iface
      server = Thread.new { s.start }

      query = Resolv::DNS::Message.new 0
      query.add_question "_test-mdns._tcp.local.", Resolv::DNS::Resource::IN::PTR
      sock = open_ipv4 iface.addr, 0
      multicast_send sock, query.encode

      service = Resolv::DNS::Name.create s.service
      service_name = Resolv::DNS::Name.create s.service_name

      while res = q.pop
        if res.answer.find { |name, ttl, data| name == service && data.name == service_name }
          wr.write "x"
          break
        end
      end

      listen.join
      s.stop
      server.join

      msg = Resolv::DNS::Message.new(0)
      msg.qr = 1
      msg.aa = 1

      msg.add_additional s.service_name, 60, MDNS::Announce::IN::SRV.new(0, 0, s.service_port, s.qualified_host)

      msg.add_additional s.qualified_host,
        60,
        MDNS::Announce::IN::A.new(iface.addr.ip_address)

      msg.add_answer s.service,
        60,
        Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(s.service_name))

      assert_equal msg.encode, res.encode
    end

    def test_service_unicast_answer
      s = make_server iface
      runner = Thread.new { s.start }

      query = Resolv::DNS::Message.new 0
      query.add_question "_test-mdns._tcp.local.", ZeroConf::PTR

      sock = open_ipv4 iface.addr, 0
      multicast_send sock, query.encode
      res = Resolv::DNS::Message.decode sock.recvfrom(2048).first
      s.stop
      runner.join

      expected = Resolv::DNS::Message.new(0)
      expected.qr = 1
      expected.aa = 1

      expected.add_additional s.service_name, 10, Resolv::DNS::Resource::IN::SRV.new(0, 0, s.service_port, s.qualified_host)
      expected.add_additional s.qualified_host,
            10,
            Resolv::DNS::Resource::IN::A.new(iface.addr.ip_address)

      expected.add_additional s.service_name,
        10,
        Resolv::DNS::Resource::IN::TXT.new(*s.text)
      expected.add_answer s.service,
        10,
        Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(s.service_name))
      expected.add_question s.service, ZeroConf::PTR

      assert_equal expected, res
    end

    def test_multicast_service_instance_answer
      q = Queue.new
      rd, wr = IO.pipe

      listen = make_listener rd, q
      s = make_server iface
      server = Thread.new { s.start }

      query = Resolv::DNS::Message.new 0
      query.add_question "tc-lan-adapter._test-mdns._tcp.local.", Resolv::DNS::Resource::IN::PTR
      sock = open_ipv4 iface.addr, 0
      multicast_send sock, query.encode

      service = Resolv::DNS::Name.create s.service
      service_name = Resolv::DNS::Name.create s.service_name

      while res = q.pop
        if res.answer.find { |name, ttl, data| name == service_name }
          wr.write "x"
          break
        end
      end

      listen.join
      s.stop
      server.join

      msg = Resolv::DNS::Message.new(0)
      msg.qr = 1
      msg.aa = 1

      msg.add_answer s.service_name, 60, Resolv::DNS::Resource::IN::SRV.new(0, 0, s.service_port, s.qualified_host)

      msg.add_additional s.qualified_host,
        60,
        Resolv::DNS::Resource::IN::A.new(iface.addr.ip_address)

      msg.add_additional service_name,
        60,
        Resolv::DNS::Resource::IN::TXT.new(*s.text)


      assert_equal msg, res
    end
  end
end
