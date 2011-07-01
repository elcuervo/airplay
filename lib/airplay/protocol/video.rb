class Airplay::Protocol::Video < Airplay::Protocol

  def resource
    "/play"
  end

  def send(video)
    # TODO: serve local file
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
