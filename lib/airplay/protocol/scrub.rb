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

  def check
    response = @http.get(resource, plist_headers)
    result = {}
    response.delete(":").split.each_slice(2) do |key, value|
      result[key] = value.to_i
    end
    result
  end

  def to(position)
    if position.to_s.include?("%")
      percent = position.to_i
      raise Airplay::Protocol::OutOfRangeError if percent > 100
      duration = check.fetch("duration")
      position = (duration*percent)/100
    end

    @http.post("#{resource}?position=#{position}\n")
  end

end

class Airplay::Protocol::OutOfRangeError < StandardError; end;
