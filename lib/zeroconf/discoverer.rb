# frozen_string_literal: true

require "zeroconf/client"

module ZeroConf
  class Discoverer < Client
    DISCOVER_QUERY = Resolv::DNS::Message.new 0
    DISCOVER_QUERY.add_question DISCOVERY_NAME, PTR

    def initialize interfaces: ZeroConf.interfaces
      super(nil, interfaces:)
    end

    private

    def interested? msg
      msg.question.length > 0 && msg.question.first.last == PTR
    end

    def get_query
      DISCOVER_QUERY
    end
  end
end
