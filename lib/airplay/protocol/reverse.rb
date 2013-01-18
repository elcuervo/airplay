require "celluloid"
require "net/ptth"
require "net/http"
require "airplay/protocol/app"

module Airplay::Protocol
  class Reverse
    include Celluloid

    attr_accessor :callbacks
    attr_reader :state

    def initialize(server, purpose = "event")
      @ptth = Net::PTTH.new(server)
      @ptth.set_debug_output = $stdout if ENV["HTTP_DEBUG"]
      @state = "disconnected"
      @purpose = purpose
      @ptth.app = Airplay.app

      @callbacks = {
        event: [],
        slideshow: []
      }

      async.pipeline
      @ptth.app.pipeline = self.async
    end

    def disconnect
      @state = "disconnected"
      @ptth.close
    end

    def connect
      request = Net::HTTP::Post.new("/reverse")
      request["X-Apple-Purpose"] = @purpose
      request["X-Apple-Session-ID"] = Airplay.session
      request["X-Apple-Device-ID"] = "0x581faa7c9754"
      request["Content-Length"] = 0

      @ptth.request(request)
      @state = "connected"
    end

    def pipeline
      loop do
        message = receive { |msg| msg.is_a? Message }
        @callbacks[message.type.to_sym].each do |callback|
          callback.call(message.content)
        end
      end
    end
  end
end
