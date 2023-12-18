# frozen_string_literal: true

require "zeroconf/client"

module ZeroConf
  class Resolver < Client
    alias :resolve :run

    private

    def get_query
      query = Resolv::DNS::Message.new 0
      query.add_question Resolv::DNS::Name.create(name), A
      query
    end
  end
end
