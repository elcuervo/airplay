require "celluloid"
require "airplay/connection/persistent"
require "airplay/connection/authentication"

module Airplay
  # Public: The class that handles all the outgoing basic HTTP connections
  #
  class Connection
    Response = Struct.new(:connection, :response)

    include Celluloid

    def initialize(device, options = {})
      @device = device
      @options = options
      @logger = Airplay::Logger.new("airplay::connection")
    end

    # Public: Establishes a persistent connection to the device
    #
    # Returns the persistent connection
    #
    def persistent
      address = @options[:address] || "http://#{@device.address}"
      @_persistent ||= Airplay::Connection::Persistent.new(address, @options)
    end

    # Public: Closes the opened connection
    #
    # Returns nothing
    #
    def close
      persistent.close
      @_persistent = nil
    end

    # Public: Executes a POST to a resource
    #
    # resource - The resource on the currently active Device
    # body     - The body of the action
    # headers  - Optional headers
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
    # resource - The resource on the currently active Device
    # body     - The body of the action
    # headers  - Optional headers
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
    # resource - The resource on the currently active Device
    # headers  - Optional headers
    #
    # Returns a response object
    #
    def get(resource, headers = {})
      @logger.info("GET #{resource}")
      request = Net::HTTP::Get.new(resource)

      send_request(request, headers)
    end

    private

    # Private: The defaults connection headers
    #
    # Returns the default headers
    #
    def default_headers
      {
        "User-Agent"         => "MediaControl/1.0",
        "X-Apple-Session-Id" => persistent.session
      }
    end

    # Private: Sends a request to the Device
    #
    # request - The Request object
    # headers - The headers of the request
    #
    # Returns a response object
    #
    def send_request(request, headers)
      request.initialize_http_header(default_headers.merge(headers))

      if @device.password?
        authentication = Airplay::Connection::Authentication.new(persistent)
        request = authentication.sign(request)
      end

      @logger.info("Sending request to #{@device.address}")
      response = persistent.request(request)

      Airplay::Connection::Response.new(persistent, response)
    end
  end
end
