require "helper"

module ZeroConf
  class ClientTest < Test
    attr_reader :iface

    def setup
      super
      @iface = ZeroConf.interfaces.find_all { |x| x.addr.ipv4? }.first
    end

    def test_resolve
      s = make_server iface, "coolhostname"
      runner = Thread.new { s.start }
      Thread.pass until s.started?
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
      s = make_server iface, "coolhostname"
      runner = Thread.new { s.start }
      Thread.pass until s.started?
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
      s = make_server iface
      runner = Thread.new { s.start }
      Thread.pass until s.started?
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
      s = make_server iface
      runner = Thread.new { s.start }
      Thread.pass until s.started?
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
      s = make_server iface
      runner = Thread.new { s.start }
      Thread.pass until s.started?
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
      s = make_server iface
      runner = Thread.new { s.start }
      Thread.pass until s.started?
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
