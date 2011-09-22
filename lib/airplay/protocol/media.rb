class Airplay::Protocol::Media

  def initialize(protocol_handler)
    @http = protocol_handler
    @scrubber = Airplay::Protocol::Scrub.new(protocol_handler)
  end

  def resource
    "/play"
  end

  def stop_resource
    "/stop"
  end

  def pause_resource
    "/rate"
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
    raise Airplay::Protocol::InvalidMediaError if (media =~ URI::regexp).nil?
    body  = location_body(media)
    body += position_body(position.to_s)
    @http.post(resource, body)
  end

  def pause
    rate(0)
  end

  def scrub(position = false)
    if position
      @scrubber.to position
    else
      @scrubber.check
    end
  end

  def resume
    rate(1)
  end

  def rate(play = 1)
    @http.post("#{pause_resource}?value=#{play}")
  end

  def stop
    @http.post(stop_resource)
  end

end
