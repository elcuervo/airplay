require "forwardable"

require "airplay/structure"
require "airplay/connection"
require "airplay/client"

module Airplay
  class << self
    extend Forwardable

    def_delegators :client, :nodes, :active, :use, :view, :slideshow

    def connection
      @_connection ||= Connection.new
    end

    private

    def client
      @_client ||= Client.new
    end
  end
end
