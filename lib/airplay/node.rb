require "airplay/structure"

module Airplay
  # Public: Represents an Airplay Node
  #

  Node = Structure.new(:name, :address, :password) do
    attr_accessor :features

    def initialize(*)
      super
    end

    def ip
      @_ip ||= address.split(":").last
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
