require "net/http/persistent"
require "uuid"

module Airplay
  # Public: The class that handles all the outgoing basic HTTP connections
  #
  class Connection
    # Public: Class that wraps a persistent connection to point to the airplay
    #         server and other configuration
    #
    class Persistent < ::Net::HTTP::Persistent
      def initialize(*)
        super
        @logger = Airplay::Logger.new("airplay::connection::persistent")

        @idle_timeout = nil
        @name = UUID.generate
        @keep_alive = 30*24
        @retry_change_requests = true
        @debug_output = @logger
      end

      # Public: send a request to the active server
      #
      #   request - The Net::HTTP request to be executed
      #   &block  - An optional block to be executed within the block
      #
      def request(request, request_uri = nil, &block)
        server = Airplay.active
        request_uri ||= uri(request)
        @logger.info("Sending request to #{server.name} (#{server.address})")
        super(request_uri, request, &block)
      end

      def uri(request)
        server = Airplay.active
        path = "http://#{server.address}#{request.path}"
        URI.parse(path)
      end
    end
  end
end
