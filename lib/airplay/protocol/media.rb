class Airplay::Protocol::Media

  def initialize(protocol_handler)
    @http = protocol_handler
  end

  def resource
    "/play"
  end

  def stop_resource
    "/stop"
  end

  def position_body(position = 0)
    "Start-Position: #{position}\n"
  end

  def location_body(media)
    "Content-Location: #{media}\n"
  end

  def send(media, position = 0)
    play(media, position)
    self
  end

  def play(media, position = 0)
    body  = location_body(media)
    body += position_body(position.to_s)
    @http.post(resource, body)
  end

  def stop
    @http.post(stop_resource)
  end

end
