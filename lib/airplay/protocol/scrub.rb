class Airplay::Protocol::Scrub

  def initialize(protocol_handler)
    @http = protocol_handler
  end

  def resource
    "/scrub"
  end

  def plist_headers
    {'Content-Type' => 'text/x-apple-plist+xml'}
  end

  def send
    response = @http.get(resource, plist_headers)
    result = {}
    response.delete(":").split.each_slice(2) do |key, value|
      result[key] = value
    end
    result
  end

end
