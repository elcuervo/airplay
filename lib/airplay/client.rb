require "celluloid"
require "net/http/persistent"
require "airplay/browser"
require "airplay/protocol"
require "airplay/client/events"

module Airplay
  class Client
    attr_reader :active

    def initialize(node = false, browser = Browser)
      @browser = browser.new
      @browser.browse
    end

    def use(node_name)
      @active = if node_name.is_a?(Airplay::Node)
                  node_name
                else
                  nodes.find_by_name(node_name)
                end
    end

    def view(media_or_io, options = {})
      handler = Airplay::Protocol::Image.new(media_or_io, options)
      handler.broadcast
    end

    def nodes
      @browser.nodes
    end

    def active
      @active ||= @browser.nodes.first
    end
  end
end
