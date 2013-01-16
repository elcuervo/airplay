module Airplay
  class Connection
    DEFAULT_HEADERS = { "User-Agent" => "MediaControl/1.0" }

    def initialize
      @http = Net::HTTP::Persistent.new
      @http.idle_timeout = nil
      @http.retry_change_requests = true
      @http.debug_output = $stdout if ENV.has_key?('HTTP_DEBUG')
    end

    def post(resource, body, headers = {})
      request = Net::HTTP::Post.new(resource)
      request.body = body

      send_request(request, headers)
    end

    def get(resource, headers = {})
      request = Net::HTTP::Get.new(resource)

      send_request(request, headers)
    end

    def send_request(request, headers)
      server = Airplay.active
      path = "http://#{server.ip}:#{server.port}#{request.path}"
      uri = URI.parse(path)

      request.initialize_http_header(DEFAULT_HEADERS.merge(headers))
      @http.request(uri, request)
    end
  end
end
