require "celluloid"
require "net/ptth"
require "net/http"
require "airplay/protocol/app"
require "airplay/connection/authentication"

module Airplay::Protocol
  # Public: Handles the reverse connection
  #
  class Reverse
    include Celluloid

    attr_accessor :callbacks
    attr_reader   :state

    def initialize(device, purpose = "event")
      @logger = Airplay::Logger.new("airplay::protocol::reverse")

      @ptth = Net::PTTH.new("http://#{device.address}")
      @ptth.set_debug_output = @logger
      @state = "disconnected"
      @purpose = purpose
      @ptth.app = Airplay.app

      @callbacks = []

      async.pipeline
      @ptth.app.pipeline = self.async
    end

    # Public: Disconnects the current connection
    #
    def disconnect
      @state = "disconnected"
      @ptth.close
    end

    # Public: Connects to the reverse resource and starts the switching
    #
    def connect
      @logger.info "Connecting with purpose: #{@purpose}"

      request = Net::HTTP::Post.new("/reverse")

      request["X-Apple-Purpose"] = @purpose
      request["X-Apple-Device-ID"] = "0x581faa7c9754"

      if Airplay.active.password?
        authentication = Airplay::Connection::Authentication.new(@ptth)
        request = authentication.sign(request)
      end

      @ptth.request(request)
      @state = "connected"
    end

    # Public: Pipelines all the incomming messages to the callback ppol
    #
    def pipeline
      loop do
        message = receive { |msg| msg.is_a? Message }
        @logger.debug "Incomming message from the event pipeline: #{message}"
        @callbacks.each do |callback|
          callback.call(message.content)
        end
      end
    end
  end
end
