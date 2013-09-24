require "airplay/structure"

module Airplay
  # Public: Represents an Airplay Node
  #
  class Node < Structure.new(:name, :address, :domain, :password)
    attr_accessor :features, :ip, :port, :info

    def initialize(*)
      super
      parse_address
    end

    # Public: Parses features of a given feature list
    #
    #   info: The info fetched from the text record
    #
    def parse_info(info)
      @info = Info.create(info)
      @features = Features.load(info.fetch("features", "0").hex)
    end

    def password?
      !!password && !password.empty?
    end

    private

    # Private: Parses ip and port information
    #
    def parse_address
      @ip, port = address.split(":")
      @port = port.to_i
    end
  end
end

require "airplay/node/info"
require "airplay/node/features"
