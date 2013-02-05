require "forwardable"
require "uuid"

require "airplay/structure"
require "airplay/connection"
require "airplay/client"

module Airplay
  class << self
    extend Forwardable

    def_delegators :client, :nodes, :active, :use, :view, :slideshow, :app,
                   :stop, :play, :player

    def session
      @_session ||= UUID.generate
    end

    def connection
      @_connection ||= Connection.new
    end

    private

    def client
      @_client ||= Client.new
    end
  end
end
