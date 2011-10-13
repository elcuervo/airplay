class Airplay::Protocol
  attr_reader :host, :resource, :request

  DEFAULT_HEADERS = { "User-Agent" => "MediaControl/1.0" }
  SEARCH          = '_airplay._tcp.'
  PORT            = 7000

  def initialize(host, port, password)
    @device = { :host => host, :port => port }
    @password = password
    @http = Net::HTTP::Persistent.new
    @http.debug_output = $stdout if ENV.has_key?('HTTP_DEBUG')
  end

  def make_request(request)
    uri = URI.parse "http://#{@device.fetch(:host)}:#{@device.fetch(:port)}#{request.path}"
    uri.user = "Airplay"
    uri.password = @password

    response = @http.request(uri, request) {}
    if response['www-authenticate']
      digest_auth = Net::HTTP::DigestAuth.new
      authentication = digest_auth.auth_header uri, response['www-authenticate'], request.method
      request.add_field 'Authorization', authentication
      response = @http.request(uri, request) {}
    end

    raise Airplay::Protocol::InvalidRequestError if response.code == "404"
    response.body
  end

  def put(resource, body = nil, headers = {})
    request = Net::HTTP::Put.new resource
    request.body = body
    request.initialize_http_header DEFAULT_HEADERS.merge(headers)
    make_request(request)
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
class Airplay::Protocol::InvalidMediaError   < StandardError; end
