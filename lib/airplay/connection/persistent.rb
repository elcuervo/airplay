require "net/http"
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
        ip, port = address.split(":")
        @http = Net::HTTP.new(ip, port)

        @session = SecureRandom.uuid
        @mac_address = "0x#{SecureRandom.hex(6)}"
      end

      def close
        @http.close
      end

      # Public: send a request to the active server
      #
      #   request - The Net::HTTP request to be executed
      #   &block  - An optional block to be executed within the block
      #
      def request(request)
        @http.request(request)
      end
    end
  end
end
