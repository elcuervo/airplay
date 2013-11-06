require "net/ptth"
require "securerandom"

module Airplay
  # Public: The class that handles all the outgoing basic HTTP connections
  #
  class Connection
    # Public: Class that wraps a persistent connection to point to the airplay
    #         server and other configuration
    #
    class Persistent
      attr_reader :session, :mac_address

      def initialize(address, options = {})
        @logger = Airplay::Logger.new("airplay::connection::persistent")
        @socket = Net::PTTH.new(address, options)
        @socket.set_debug_output = @logger

        @session = SecureRandom.uuid
        @mac_address = "0x#{SecureRandom.hex(6)}"

        @socket.socket
      end

      def close
        socket.close
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
