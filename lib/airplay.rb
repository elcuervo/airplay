require "airplay/configuration"
require "airplay/browser"

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
      browse if browser.nodes.empty?
      browser.nodes
    end

    def configuration
      @_configuration ||= Configuration.new
    end

    def [](node_name)
      nodes.find_by_name(node_name)
    end

    private

    def browser
      @_browser ||= Browser.new
    end
  end
end

