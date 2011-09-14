class Airplay::Protocol::Media

  def initialize(protocol_handler)
    @http = protocol_handler
  end

  def resource
    "/play"
  end

  def position_body(position = 0)
    "Start-Position: #{position}\n"
  end

  def location_body(video)
    "Content-Location: #{video}\n"
  end

  def send(media, position = 0)
    body  = location_body(media)
    body += position_body(position.to_s)
    @http.post(resource, body)
  end

  def play
  end

  def pause
    # TODO: know how to pause video
  end

  def stop
  end

end
