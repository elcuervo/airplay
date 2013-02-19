require "celluloid"

module Airplay
  # Public: The class that handles all the outgoing basic HTTP connections
  #
  class Connection
    attr_accessor :reverse, :events

    include Celluloid

    def initialize
      @logger = Log4r::Logger.new("airplay::connection")
      @logger.outputters = Log4r::Outputter.stdout
      @http = Net::HTTP::Persistent.new
      @reverse = Airplay::Protocol::Reverse.new(Airplay.active)

      @reverse.async.connect
      @http.idle_timeout = nil
      @http.retry_change_requests = true
      @http.debug_output = $stdout if ENV.has_key?('HTTP_DEBUG')
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

    # Private: Sends a request to the Node
    #
    #   request - The Request object
    #   headers - The headers of the request
    #
    # Returns a response object
    #
    def send_request(request, headers)
      default_headers = {
        "User-Agent"         => "MediaControl/1.0",
        "X-Apple-Session-Id" => Airplay.session
      }

      server = Airplay.active
      path = "http://#{server.ip}:#{server.port}#{request.path}"
      uri = URI.parse(path)

      request.initialize_http_header(default_headers.merge(headers))
      @logger.info("Sending request to #{server.name} (#{server.ip}:#{server.port})")
      @http.request(uri, request) {}
    end
  end
end
