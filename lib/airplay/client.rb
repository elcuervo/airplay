require "celluloid"
require "net/http/persistent"
require "airplay/browser"

module Airplay
  class Client
    class Connection
      include Celluloid

      def initialize(name, uri, request)
        @http = Net::HTTP::Persistent.new(name)
        @http.idle_timeout = nil
        @http.debug_output = $stdout if ENV.has_key?('HTTP_DEBUG')
        @http.request(uri, request)
      end
    end

    attr_reader :active

    def initialize(node = false, browser = Browser)
      @browser = browser.new
      @browser.browse
    end

    def use(node_name)
      @active = nodes.find_by_name(node_name)
    end

    def connections
      @_connections ||= begin
        uri = URI.parse("http://#{active.address}")
        events = Net::HTTP::Post.new("/server-info")

        [
          Connection.new(:events,   uri, events),
          Connection.new(:outbound, uri, events)
        ]
      end
    end

    def nodes
      @browser.nodes
    end

    def active
      @active ||= @browser.nodes.first
    end
  end
end
