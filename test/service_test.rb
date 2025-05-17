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

    def test_raises_when_creating_a_service_with_dot_in_the_name
      assert_raises ArgumentError do
        Service.new "_test-mdns._tcp.local.", 42424,
          "some.subdomain.workstation"
      end

      assert_raises ArgumentError do
        Service.new "_test-mdns._tcp.local.", 42424,
          "ruby-mdns", instance_name: "ruby.test"
      end
    end

    def test_sets_correct_service_name_from_instance_name
      s = Service.new "_test-mdns._tcp.local.", 42424,
        "my-rb-service", instance_name: "My RB service"
      assert_equal "my-rb-service.local.", s.qualified_host
      assert_equal "My RB service._test-mdns._tcp.local.", s.service_name
    end

    def test_removes_dot_local_tld_from_passed_hostname
      s = Service.new "_test-mdns._tcp.local.", 42424,
        "ThisMac.local"
      assert_equal "ThisMac.local.", s.qualified_host
      assert_equal "ThisMac._test-mdns._tcp.local.", s.service_name

      s = Service.new "_test-mdns._tcp.local.", 42424,
        "ThisMac.local."
      assert_equal "ThisMac.local.", s.qualified_host
      assert_equal "ThisMac._test-mdns._tcp.local.", s.service_name
    end

    def test_unicast_service_instance_answer
      latch = Queue.new
      s = make_server iface, started_callback: -> { latch << :start }
      runner = Thread.new { s.start }
      latch.pop

      query = Resolv::DNS::Message.new 0
      query.add_question "tc-lan-adapter._test-mdns._tcp.local.", SRV

      sock = open_ipv4 iface.addr, 0
      multicast_send sock, query.encode
      res = Resolv::DNS::Message.decode read_with_timeout(sock).first
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
      expected.add_question s.service_name, MDNS::Announce::IN::SRV

      assert_equal expected, res
    end

    def test_multicast_discover
      q = Queue.new
      rd, wr = IO.pipe

      listen = make_listener rd, q
      latch = Queue.new
      s = make_server iface, started_callback: -> { latch << :start }
      server = Thread.new { s.start }
      latch.pop

      query = Resolv::DNS::Message.new 0
      query.add_question "_services._dns-sd._udp.local.", Resolv::DNS::Resource::IN::PTR
      sock = open_ipv4 iface.addr, 0
      multicast_send sock, query.encode

      while res = q.pop
        if res.answer.find { |name, ttl, data| name.to_s == "_services._dns-sd._udp.local" && data.name.to_s == SERVICE }
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

      assert_equal msg, res
    end

    def test_announcement
      # FIXME: this test should be converted to an integration test.
      # We need to make a client listen for the announcement and then decode that
      service = Service.new "_test-mdns._tcp.local.", 42424

      msg = Resolv::DNS::Message.new(0)
      msg.qr = 1
      msg.aa = 1

      msg.add_additional service.service_name, 60, MDNS::Announce::IN::SRV.new(0, 0, service.service_port, service.qualified_host)

      service.service_interfaces.each do |iface|
        if iface.addr.ipv4?
          msg.add_additional service.qualified_host,
            60,
            MDNS::Announce::IN::A.new(iface.addr.ip_address)
        else
          msg.add_additional service.qualified_host,
            60,
            MDNS::Announce::IN::AAAA.new(iface.addr.ip_address)
        end
      end

      if service.text
        msg.add_additional service.service_name,
          60,
          MDNS::Announce::IN::TXT.new(*service.text)
      end

      msg.add_answer service.service,
        60,
        Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(service.service_name))

      assert_equal msg, service.announcement
    end

    def test_disconnect
      # FIXME: this test should be converted to an integration test.
      # We need to make a client listen for the disconnect and then decode that
      s = make_server iface

      msg = Resolv::DNS::Message.new(0)
      msg.qr = 1
      msg.aa = 1

      msg.add_additional s.service_name, 0, Resolv::DNS::Resource::IN::SRV.new(0, 0, s.service_port, s.qualified_host)

      s.service_interfaces.each do |iface|
        if iface.addr.ipv4?
          msg.add_additional s.qualified_host,
            0,
            Resolv::DNS::Resource::IN::A.new(iface.addr.ip_address)
        else
          msg.add_additional s.qualified_host,
            0,
            Resolv::DNS::Resource::IN::AAAA.new(iface.addr.ip_address)
        end
      end

      if s.text
        msg.add_additional s.service_name,
          0,
          Resolv::DNS::Resource::IN::TXT.new(*s.text)
      end

      msg.add_answer s.service,
        0,
        Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(s.service_name))

      assert_equal msg, s.disconnect_msg
    end

    def test_dnssd_unicast_answer
      latch = Queue.new
      s = make_server iface, started_callback: -> { latch << :start }
      runner = Thread.new { s.start }
      latch.pop

      query = Resolv::DNS::Message.new 0
      query.add_question "_services._dns-sd._udp.local.", PTR

      sock = open_ipv4 iface.addr, 0
      multicast_send sock, query.encode

      res = nil
      loop do
        buf, from = read_with_timeout sock
        res = Resolv::DNS::Message.decode buf
        if from.last == iface.addr.ip_address
          break if res.answer.find { |name, ttl, data| data.name.to_s == SERVICE }
        end
      end

      s.stop
      runner.join

      expected = Resolv::DNS::Message.new(0)
      expected.qr = 1
      expected.aa = 1

      expected.add_answer DISCOVERY_NAME, 10,
        Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(s.service))

      expected.add_question DISCOVERY_NAME, PTR

      assert_equal expected, res
    end

    def test_service_multicast_answer
      q = Thread::Queue.new
      rd, wr = IO.pipe

      latch = Queue.new
      listen = make_listener rd, q, started_callback: -> { latch << :start }
      s = make_server iface, started_callback: -> { latch << :start }
      server = Thread.new { s.start }
      latch.pop
      latch.pop

      query = Resolv::DNS::Message.new 0
      query.add_question "_test-mdns._tcp.local.", Resolv::DNS::Resource::IN::PTR
      sock = open_ipv4 iface.addr, 0
      multicast_send sock, query.encode

      service = Resolv::DNS::Name.create s.service
      service_name = Resolv::DNS::Name.create s.service_name

      while res = q.pop
        if res.answer.find { |name, ttl, data| name == service && data.name == service_name } &&
            res.additional.find { |_, _, data| ZeroConf::MDNS::Announce::IN::SRV == data.class }
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

      msg.add_additional s.service_name,
        60,
        MDNS::Announce::IN::TXT.new(*s.text)

      msg.add_answer s.service,
        60,
        Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(s.service_name))

      assert_equal msg, res
    end

    def test_service_unicast_answer
      latch = Queue.new
      s = make_server iface, started_callback: -> { latch << :start }
      runner = Thread.new { s.start }
      latch.pop

      query = Resolv::DNS::Message.new 0
      query.add_question "_test-mdns._tcp.local.", PTR

      sock = open_ipv4 iface.addr, 0
      multicast_send sock, query.encode
      res = Resolv::DNS::Message.decode read_with_timeout(sock).first
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
      expected.add_question s.service, PTR

      assert_equal expected, res
    end

    def test_multicast_service_instance_answer
      q = Queue.new
      rd, wr = IO.pipe

      latch = Queue.new
      listen = make_listener rd, q, started_callback: -> { latch << :start }
      s = make_server iface, started_callback: -> { latch << :start }
      server = Thread.new { s.start }
      latch.pop
      latch.pop

      query = Resolv::DNS::Message.new 0
      query.add_question "tc-lan-adapter._test-mdns._tcp.local.", Resolv::DNS::Resource::IN::PTR
      sock = open_ipv4 iface.addr, 0
      multicast_send sock, query.encode

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

    def test_unicast_name_lookup
      latch = Queue.new
      s = make_server iface, started_callback: -> { latch << :start }
      runner = Thread.new { s.start }
      latch.pop

      query = Resolv::DNS::Message.new 0
      query.add_question "tc-lan-adapter.local.", A

      sock = open_ipv4 iface.addr, 0
      multicast_send sock, query.encode
      res = Resolv::DNS::Message.decode read_with_timeout(sock).first
      s.stop
      runner.join

      expected = Resolv::DNS::Message.new(0)
      expected.qr = 1
      expected.aa = 1

      expected.add_answer s.qualified_host, 10, Resolv::DNS::Resource::IN::A.new(iface.addr.ip_address)

      expected.add_additional s.service_name,
        10,
        Resolv::DNS::Resource::IN::TXT.new(*s.text)

      expected.add_question s.qualified_host,
        MDNS::Announce::IN::A

      assert_equal expected, res
    end

    def test_multicast_name
      q = Queue.new
      rd, wr = IO.pipe

      latch = Queue.new
      listen = make_listener rd, q, started_callback: -> { latch << :start }
      s = make_server iface, started_callback: -> { latch << :start }
      server = Thread.new { s.start }
      latch.pop
      latch.pop

      query = Resolv::DNS::Message.new 0
      query.add_question "tc-lan-adapter.local.", Resolv::DNS::Resource::IN::A
      sock = open_ipv4 iface.addr, 0
      multicast_send sock, query.encode

      host = Resolv::DNS::Name.create s.qualified_host

      while res = q.pop
        if res.answer.find { |name, ttl, data| name == host }
          wr.write "x"
          break
        end
      end

      listen.join
      s.stop
      server.join

      expected = Resolv::DNS::Message.new(0)
      expected.qr = 1
      expected.aa = 1

      expected.add_answer s.qualified_host, 60, Resolv::DNS::Resource::IN::A.new(iface.addr.ip_address)

      expected.add_additional s.service_name,
        60,
        Resolv::DNS::Resource::IN::TXT.new(*s.text)

      assert_equal expected, res
    end

    def test_raise_on_malformed_requests
      latch = Queue.new
      s = make_server iface, abort_on_malformed_requests: true, started_callback: -> { latch << :start }
      runner = Thread.new {
        assert_raises do
          s.start
        end
      }
      latch.pop

      sock = open_ipv4 iface.addr, Resolv::MDNS::Port
      multicast_send sock, "not a valid DNS message"
      runner.join
    end

    def read_with_timeout sock
      return unless sock.wait_readable(3)
      sock.recvfrom(2048)
    end
  end
end
