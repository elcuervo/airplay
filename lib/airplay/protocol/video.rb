class Airplay::Protocol::Video < Airplay::Protocol

  def resource
    "/play"
  end

  def position_body(position = 0)
    "Start-Position: #{position}\n"
  end

  def location_body(video)
    "Content-Location: #{video}\n"
  end

  def send(video, position = 0)
    body  = location_body(video)
    body += position_body(position.to_s)
    post(resource, body)
  end

  def play
  end

  def pause
    # TODO: know how to pause video
  end

  def stop
  end

  def scrub
  end

end
