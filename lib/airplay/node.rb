require "airplay/structure"
require "airplay/playable"

module Airplay
  # Public: Represents an Airplay Node
  #

  Node = Structure.new(:name, :address, :password) do
    attr_accessor :features

    include Playable

    def initialize(*)
      super

      Airplay.configuration.load
    end

    def ip
      @_ip ||= address.split(":").first
    end

    def resolution
    end

    def password=(passwd)
      @password = passwd
    end

    def password?
      !!password && !password.empty?
    end

    private

    def get_features
    end

    # Private: Parses features of a given feature list
    #
    #   info: The info fetched from the text record
    #
    def parse_info(info)
      @features = Features.load(info.fetch("features", "0").hex)
    end
  end
end

require "airplay/node/features"
