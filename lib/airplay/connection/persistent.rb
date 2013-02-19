require "net/http/persistent"
require "uuid"

module Airplay
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
      def request(request, &block)
        server = Airplay.active
        path = "http://#{server.address}#{request.path}"
        uri = URI.parse(path)
        @logger.info("Sending request to #{server.name} (#{server.ip}:#{server.port})")
        super(uri, request, &block)
      end
    end
  end
end
