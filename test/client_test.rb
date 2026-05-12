require "helper"

module ZeroConf
  # Mimics responders like Nanoleaf which place SRV in the answer section of
  # the PTR response instead of in the additional section. See
  # https://github.com/tenderlove/zeroconf/issues/10
  class NanoleafService < Service
    private

    def service_unicast_answer
      msg = Resolv::DNS::Message.new(0)
      msg.qr = 1
      msg.aa = 1

      # SRV goes in ANSWER (Nanoleaf-style), not additional
      msg.add_answer service_name, 10,
        Resolv::DNS::Resource::IN::SRV.new(0, 0, service_port, qualified_host)

      service_interfaces.each do |iface|
        if iface.addr.ipv4?
          msg.add_additional qualified_host, 10,
            Resolv::DNS::Resource::IN::A.new(iface.addr.ip_address)
        else
          msg.add_additional qualified_host, 10,
            Resolv::DNS::Resource::IN::AAAA.new(iface.addr.ip_address)
        end
      end

      if @text
        msg.add_additional service_name, 10,
          Resolv::DNS::Resource::IN::TXT.new(*@text)
      end

      msg.add_answer service, 10,
        Resolv::DNS::Resource::IN::PTR.new(Resolv::DNS::Name.create(service_name))

      msg.add_question service, PTR

      msg
    end
  end

  class ClientTest < Test
    attr_reader :iface

    def setup
      super
      @iface = ZeroConf.interfaces.find_all { |x| x.addr.ipv4? }.first
    end

    # Regression test for https://github.com/tenderlove/zeroconf/issues/10
    # If a responder places SRV in the answer section (rather than additional),
    # find_addrinfos must still return a usable [host, Addrinfo] tuple instead
    # of crashing with "no implicit conversion from nil to integer".
    def test_find_addrinfos_with_srv_in_answer
      latch = Queue.new
      s = NanoleafService.new SERVICE + ".",
        42424,
        HOST_NAME,
        service_interfaces: [iface],
        text: ["test=1", "other=value"],
        started_callback: -> { latch << :start }
      runner = Thread.new { s.start }
      latch.pop

      addrinfos = ZeroConf.find_addrinfos(SERVICE, timeout: 1)

      s.stop
      runner.join

      ours = addrinfos.find { |host, _| host == "#{HOST_NAME}.local" }
      assert ours, "expected to find #{HOST_NAME}.local in #{addrinfos.inspect}"
      host, addr = ours
      assert_equal "#{HOST_NAME}.local", host
      assert_equal 42424, addr.ip_port
      assert_equal iface.addr.ip_address, addr.ip_address
    end

    def test_resolve
      latch = Queue.new
      s = make_server iface, "coolhostname", started_callback: -> { latch << :start }
      runner = Thread.new { s.start }
      latch.pop
      found = nil

      name = "coolhostname.local"

      took = time_it do
        ZeroConf.resolve name do |msg|
          if msg.answer.find { |d, _, _| d.to_s == name }
            found = msg
          end
        end
      end

      s.stop
      runner.join

      assert found
      assert_in_delta 3, took, 0.2
    end

    def test_resolve_returns_early
      latch = Queue.new
      s = make_server iface, "coolhostname", started_callback: -> { latch << :start }
      runner = Thread.new { s.start }
      latch.pop
      found = nil

      name = "coolhostname.local"

      took = time_it do
        ZeroConf.resolve name do |msg|
          if msg.answer.find { |d, _, _| d.to_s == name }
            found = msg
            :done
          end
        end
      end

      s.stop
      runner.join

      assert found
      assert_operator took, :<, 2
    end

    def test_discover_works
      latch = Queue.new
      s = make_server iface, started_callback: -> { latch << :start }
      runner = Thread.new { s.start }
      latch.pop
      found = nil

      took = time_it do
        ZeroConf.discover do |msg|
          if msg.answer.find { |_, _, d| d.name.to_s == SERVICE }
            found = msg
          end
        end
      end

      s.stop
      runner.join

      assert found
      assert_in_delta 3, took, 0.2
    end

    def test_discover_return_early
      latch = Queue.new
      s = make_server iface, started_callback: -> { latch << :start }
      runner = Thread.new { s.start }
      latch.pop
      found = nil

      took = time_it do
        found = ZeroConf.discover do |msg|
          if msg.answer.find { |_, _, d| d.name.to_s == SERVICE }
            :done
          end
        end
      end

      s.stop
      runner.join

      assert found
      assert_operator took, :<, 2
    end

    def test_browse
      latch = Queue.new
      s = make_server iface, started_callback: -> { latch << :start }
      runner = Thread.new { s.start }
      latch.pop
      found = nil

      took = time_it do
        ZeroConf.browse SERVICE do |msg|
          if msg.question.find { |name, type| name.to_s == SERVICE && type == PTR }
            found = msg
          end
        end
      end

      s.stop
      runner.join

      assert found
      assert_equal Resolv::DNS::Name.create(SERVICE_NAME + "."), found.answer.first.last.name
      assert_in_delta 3, took, 0.2
    end

    def test_browse_returns_early
      latch = Queue.new
      s = make_server iface, started_callback: -> { latch << :start }
      runner = Thread.new { s.start }
      latch.pop
      found = nil

      took = time_it do
        found = ZeroConf.browse SERVICE do |msg|
          if msg.question.find { |name, type| name.to_s == SERVICE && type == PTR }
            :done
          end
        end
      end

      s.stop
      runner.join

      assert found
      assert_equal Resolv::DNS::Name.create(SERVICE_NAME + "."), found.answer.first.last.name
      assert_operator took, :<, 2
    end
  end
end
