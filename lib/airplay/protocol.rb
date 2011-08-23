class Airplay::Protocol
  attr_reader :host, :resource, :request

  DEFAULT_HEADERS = {"User-Agent" => "MediaControl/1.0"}
  SEARCH          = '_airplay._tcp.'
  PORT            = 7000

  def initialize(host, port = PORT)
    @http = Net::HTTP.new(host, port)
    @http.set_debug_output($stdout) if ENV.has_key?('HTTP_DEBUG')
  end

  def make_async_request(request)
    Thread.new { |t| make_request(request) }
    true
  end

  def make_request(request)
    response = @http.request(request)
    raise Airplay::Protocol::InvalidRequestError if response.code == "404"
    response
  end

  def put(resource, body = nil, headers = {})
    request = Net::HTTP::Put.new resource
    request.body = body
    request.initialize_http_header DEFAULT_HEADERS.merge(headers)
    make_async_request(request)
  end

 def post(resource, body = nil, headers = {})
    request = Net::HTTP::Post.new resource
    request.body = body
    request.initialize_http_header DEFAULT_HEADERS.merge(headers)
    make_request(request)
  end

  def get(resource, headers = {})
    request = Net::HTTP::Get.new resource
    request.initialize_http_header DEFAULT_HEADERS.merge(headers)
    make_request(request)
  end

end

class Airplay::Protocol::InvalidRequestError < StandardError; end
