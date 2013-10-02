require "net/ptth"
require "uuid"

module Airplay
  # Public: The class that handles all the outgoing basic HTTP connections
  #
  class Connection
    # Public: Class that wraps a persistent connection to point to the airplay
    #         server and other configuration
    #
    class Persistent
      def initialize(options = {})
        @logger = Airplay::Logger.new("airplay::connection::persistent")
        @socket = Net::PTTH.new("http://" + Airplay.active.address, options)
        @name = UUID.generate
        @socket.set_debug_output = @logger

        @socket.socket
      end

      def socket
        @socket.socket
      end

      # Public: send a request to the active server
      #
      #   request - The Net::HTTP request to be executed
      #   &block  - An optional block to be executed within the block
      #
      def request(request)
        @socket.request(request)
      end
    end
  end
end
