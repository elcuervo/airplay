class Airplay::Protocol
  attr_reader :host, :resource, :request

  DEFAULT_HEADERS = {"User-Agent" => "MediaControl/1.0"}
  SEARCH          = '_airplay._tcp.'
  PORT            = 7000

  def initialize(host, port = PORT)
    @http = Net::HTTP.new(host, port)
    @http.set_debug_output($stdout) if ENV.has_key?('HTTP_DEBUG')
  end

  def put(resource, body = nil, headers = {})
    @request = Net::HTTP::Put.new resource
    @request.body = body
    @request.initialize_http_header DEFAULT_HEADERS.merge(headers)
    response = @http.request(@request)
    raise Airplay::Protocol::InvalidRequestError if response.code == 404
    true
  end

end

class Airplay::Protocol::InvalidRequestError < StandardError; end
