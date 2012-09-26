require "forwardable"

require "airplay/structure"
require "airplay/client"

module Airplay
  class << self
    extend Forwardable

    def_delegators :client, :nodes, :active

    private

    def client
      @_client ||= Client.new
    end
  end
end
