require "celluloid"
require "airplay/connection/persistent"

module Airplay
  # Public: The class that handles all the outgoing basic HTTP connections
  #
  class Connection
    attr_accessor :reverse, :events

    include Celluloid

    def initialize
      @logger = Airplay::Logger.new("airplay::connection")

      @persistent = Airplay::Connection::Persistent.new
      @reverse = Airplay::Protocol::Reverse.new(Airplay.active)

      @reverse.async.connect
    end

    # Public: Executes a POST to a resource
    #
    #   resource - The resource on the currently active Node
    #   body - The body of the action
    #   headers - Optional headers
    #
    # Returns a response object
    #
    def post(resource, body = "", headers = {})
      @logger.info("POST #{resource} with #{body.bytesize} bytes")
      request = Net::HTTP::Post.new(resource)
      request.body = body

      send_request(request, headers)
    end

    # Public: Executes a PUT to a resource
    #
    #   resource - The resource on the currently active Node
    #   body - The body of the action
    #   headers - Optional headers
    #
    # Returns a response object
    #
    def put(resource, body = "", headers = {})
      @logger.info("PUT #{resource} with #{body.bytesize} bytes")
      request = Net::HTTP::Put.new(resource)
      request.body = body

      send_request(request, headers)
    end

    # Public: Executes a GET to a resource
    #
    #   resource - The resource on the currently active Node
    #   headers - Optional headers
    #
    # Returns a response object
    #
    def get(resource, headers = {})
      @logger.info("GET #{resource}")
      request = Net::HTTP::Get.new(resource)

      send_request(request, headers)
    end

    private

    def default_headers
      {
        "User-Agent"         => "MediaControl/1.0",
        "X-Apple-Session-Id" => Airplay.session
      }
    end

    # Private: Sends a request to the Node
    #
    #   request - The Request object
    #   headers - The headers of the request
    #
    # Returns a response object
    #
    def send_request(request, headers)
      server = Airplay.active
      path = "http://#{server.address}#{request.path}"
      uri = URI.parse(path)

      request.initialize_http_header(default_headers.merge(headers))
      @logger.info("Sending request to #{server.name} (#{server.address})")
      @persistent.request(request) {}
    end
  end
end
