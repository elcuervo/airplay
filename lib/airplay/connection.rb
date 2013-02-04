require "celluloid"

module Airplay
  class Connection
    attr_accessor :reverse

    include Celluloid

    def initialize
      @http = Net::HTTP::Persistent.new
      @reverse = Airplay::Protocol::Reverse.new(Airplay.active)

      @reverse.async.connect
      @http.idle_timeout = nil
      @http.retry_change_requests = true
      @http.debug_output = $stdout if ENV.has_key?('HTTP_DEBUG')
    end

    def post(resource, body = "", headers = {})
      request = Net::HTTP::Post.new(resource)
      request.body = body

      send_request(request, headers)
    end

    def put(resource, body = "", headers = {})
      request = Net::HTTP::Put.new(resource)
      request.body = body

      send_request(request, headers)
    end

    def get(resource, headers = {})
      request = Net::HTTP::Get.new(resource)

      send_request(request, headers)
    end

    def send_request(request, headers)
      default_headers = {
        "User-Agent"         => "MediaControl/1.0",
        "X-Apple-Session-Id" => Airplay.session
      }

      server = Airplay.active
      path = "http://#{server.ip}:#{server.port}#{request.path}"
      uri = URI.parse(path)

      request.initialize_http_header(default_headers.merge(headers))
      @http.request(uri, request)
    end
  end
end
