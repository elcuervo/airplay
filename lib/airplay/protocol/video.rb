class Airplay::Protocol::Video < Airplay::Protocol

  def resource
    "/video"
  end

  def position_header(position = 0)
    {"Start-Position" => position}
  end

  def location_header(video)
    {"Content-Location" => video }
  end

  def send(video, position = 0)
    headers = location_header(video)
    headers.merge!(position_header(position.to_s))
    post(resource, nil, headers)
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
