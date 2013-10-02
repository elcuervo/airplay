require "airplay/browser"

require "airplay/structure"
require "airplay/configuration"
require "airplay/logger"
require "airplay/connection"
require "airplay/client"

# Public: Airplay core module
#
module Airplay
  class << self
    def configure(&block)
      yield(configuration) if block
    end

    def browse
      browser.browse
    end

    # Public: Lists found nodes
    #
    def nodes
      browser.nodes
    end

    def configuration
      @_configuration ||= Configuration.new
    end

    private

    def browser
      @_browser ||= Browser.new
    end
  end
end

