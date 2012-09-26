require "celluloid"
require "dnssd"

require "airplay/structure"
require "airplay/client"

module Airplay
  class Player
  end

  class << self
    def nodes
      client.nodes
    end

    private

    def client
      @_client ||= Client.new
    end
  end
end
