require "forwardable"
require "uuid"
require "log4r"

require "airplay/structure"
require "airplay/configuration"
require "airplay/connection"
require "airplay/client"

# Public: Airplay core module
#
module Airplay
  class << self
    extend Forwardable

    def_delegators :client, :nodes, :active, :use, :view, :slideshow, :app,
                   :stop, :play, :player

    # Public: Access the current instance session
    #
    def session
      @_session ||= UUID.generate
    end

    def configure(&block)
      yield(configuration) if block
      configuration.load
    end

    # Public: Access the connections
    #
    def connection
      @_connection ||= Connection.new
    end

    # Public: Lists all the available image transitions
    #
    def transitions
      %w(None Dissolve SlideLeft SlideRight)
    end

    def configuration
      @_configuration ||= Configuration.new
    end

    private

    # Private: The client instance
    #
    def client
      @_client ||= Client.new
    end
  end
end

# Stops any open conection
#
at_exit {
  Airplay.stop unless ENV["TEST"]
}
