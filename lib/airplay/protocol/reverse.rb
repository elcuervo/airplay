require "celluloid"
require "net/ptth"
require "net/http"
require "airplay/protocol/app"

module Airplay::Protocol
  class Reverse
    include Celluloid

    attr_accessor :callbacks

    def initialize(server)
      @ptth = Net::PTTH.new(server)
      @ptth.app = App

      @callbacks = {
        event: Proc.new {},
        slideshow: Proc.new {}
      }

      async.pipeline
      App.pipeline = self.async
    end

    def disconnect
      @ptth.close
    end

    def connect
      request = Net::HTTP::Post.new("/reverse")
      request["X-Apple-Purpose"] = "event"

      @ptth.request(request)
    end

    def pipeline
      loop do
        message = receive { |msg| msg.is_a? Message }
        @callbacks[message.type].call(message.content)
      end
    end
  end
end
