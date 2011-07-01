class Airplay::Protocol::Image < Airplay::Protocol
  def initialize(host)
    super host
    @resource = "/photos"
    @transitions = {
      none: "None",
      dissolve: "Dissolve"
    }
  end

  def send(image, transition = :none)
    request = Net::HTTP::Put.new(@resource)
    request.body = File.exists?(image) ? File.read(image) : image
    request.initialize_http_header(DEFAULT_HEADERS.merge("X-Apple-Transition" => @transitions.fetch(transition)))
    response = @client.request(request)
    raise Airplay::Protocol::InvalidRequestError if response.code == 404
    true
  end
end
