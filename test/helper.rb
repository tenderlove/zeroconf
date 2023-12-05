ENV["MT_NO_PLUGINS"] = "1"

require "minitest/autorun"
require "zeroconf"

module ZeroConf
  class Test < Minitest::Test
  end
end
