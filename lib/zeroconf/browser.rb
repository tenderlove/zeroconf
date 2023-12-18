# frozen_string_literal: true

require "zeroconf/client"

module ZeroConf
  class Browser < Client
    alias :browse :run

    private

    def get_query
      q = PTR.new(name)
      query = Resolv::DNS::Message.new 0
      query.add_question q.name, q.class
      query
    end
  end
end
