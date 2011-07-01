class Airplay::Protocol
  attr_reader :host, :resource

  DEFAULT_HEADERS = {"User-Agent" => "MediaControl/1.0"}
  SEARCH          = '_airplay._tcp.'
  PORT            = 7000

  def initialize(host)
    @client = Net::HTTP.new(host, PORT)
    @client.set_debug_output($stdout) if ENV.has_key?('HTTP_DEBUG')
  end

end

class Airplay::Protocol::InvalidRequestError < StandardError; end
