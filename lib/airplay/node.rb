require "airplay/structure"

module Airplay
  class Node < Structure.new(:name, :address, :domain)
    attr_accessor :features, :ip, :port, :info

    def initialize(*)
      super
      parse_address
    end

    def parse_info(info)
      @info = Info.create(info)
      @features = Features.load(info.fetch("features", "0").hex)
    end

    private

    def parse_address
      @ip, port = address.split(":")
      @port = port.to_i
    end
  end
end

require "airplay/node/info"
require "airplay/node/features"
