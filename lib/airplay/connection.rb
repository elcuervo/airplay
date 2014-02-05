require "celluloid/autostart"
require "airplay/connection/persistent"
require "airplay/connection/authentication"

module Airplay
  # Public: The class that handles all the outgoing basic HTTP connections
  #
  class Connection
    Response = Struct.new(:connection, :response)
    PasswordRequired = Class.new(StandardError)
    WrongPassword = Class.new(StandardError)

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
      prepare_request(:post, resource, body, headers)
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
      prepare_request(:put, resource, body, headers)
    end

    # Public: Executes a GET to a resource
    #
    # resource - The resource on the currently active Device
    # headers  - Optional headers
    #
    # Returns a response object
    #
    def get(resource, headers = {})
      prepare_request(:get, resource, nil, headers)
    end

    private

    # Private: Prepares HTTP requests for :get, :post and :put
    #
    # verb     - The http method/verb to use for the request
    # resource - The resource on the currently active Device
    # body     - The body of the action
    # headers  - The headers of the request
    #
    # Returns a response object
    #
    def prepare_request(verb, resource, body, headers)
      msg = "#{verb.upcase} #{resource}"

      request = Net::HTTP.const_get(verb.capitalize).new(resource)

      unless verb.eql?(:get)
        request.body = body
        msg.concat(" with #{body.bytesize} bytes")
      end

      @logger.info(msg)
      send_request(request, headers)
    end

    # Private: The defaults connection headers
    #
    # Returns the default headers
    #
    def default_headers
      {
        "User-Agent"         => "MediaControl/1.0",
        "X-Apple-Session-ID" => persistent.session,
        "X-Apple-Device-ID"  => persistent.mac_address
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
        authentication = Airplay::Connection::Authentication.new(@device, persistent)
        request = authentication.sign(request)
      end

      @logger.info("Sending request to #{@device.address}")
      response = persistent.request(request)

      verify_response(Airplay::Connection::Response.new(persistent, response))
    end

    # Private: Verifies response
    #
    # response - The Response object
    #
    # Returns a response object or exception
    #
    def verify_response(response)
      if response.response.status == 401
        raise PasswordRequired if !@device.password?
        raise WrongPassword if @device.password?
      end

      response
    end
  end
end
