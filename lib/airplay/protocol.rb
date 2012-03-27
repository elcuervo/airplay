class Airplay::Protocol
  attr_reader :host, :resource, :request

  DEFAULT_HEADERS = { "User-Agent" => "MediaControl/1.0" }
  SEARCH          = '_airplay._tcp.'
  PORT            = 7000

  def initialize(host, port, password)
    @device = { :host => host, :port => port }
    @password = password
    @authentications = {}
    @http = Net::HTTP::Persistent.new
    @http.idle_timeout = nil
    @http.debug_output = $stdout if ENV.has_key?('HTTP_DEBUG')
  end

  def put(resource, body = nil, headers = {})
    @request = Net::HTTP::Put.new resource
    @request.body = body
    @request.initialize_http_header DEFAULT_HEADERS.merge(headers)
    make_request
  end

 def post(resource, body = nil, headers = {})
    @request = Net::HTTP::Post.new resource
    @request.body = body
    @request.initialize_http_header DEFAULT_HEADERS.merge(headers)
    make_request
  end

  def get(resource, headers = {})
    @request = Net::HTTP::Get.new resource
    @request.initialize_http_header DEFAULT_HEADERS.merge(headers)
    make_request
  end

  private

  def make_request
    path = "http://#{@device[:host]}:#{@device[:port]}#{@request.path}"
    @uri = URI.parse(path)
    @uri.user = "Airplay"
    @uri.password = @password

    add_auth_if_needed

    response = @http.request(@uri, @request) {}

    raise Airplay::Protocol::InvalidRequestError if response.code == "404"
    response.body
  end

  def add_auth_if_needed
    if @password
      authenticate
      @request.add_field('Authorization', @authentications[@uri.path])
    end
  end

  def authenticate
    response = @http.request(@uri, @request) {}
    auth = response['www-authenticate']
    digest_authentication(auth) if auth
  end

  def digest_authentication(auth)
    digest = Net::HTTP::DigestAuth.new
    @authentications[@uri.path] ||=
      digest.auth_header(@uri, auth, @request.method)
  end

end

class Airplay::Protocol::InvalidRequestError < StandardError; end
class Airplay::Protocol::InvalidMediaError   < StandardError; end
