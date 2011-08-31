class Airplay::Protocol::Image < Airplay::Protocol

  def resource
    "/photo"
  end

  def transitions
    {
      :none => "None",
      :dissolve => "Dissolve"
    }
  end

  def transition_header(transition)
    {"X-Apple-Transition" => transitions.fetch(transition)}
  end

  def send(image, transition = :none)
    image = image.path if image.class == File
    body = File.exists?(image) ? File.read(image) : image
    put(resource, body, transition_header(transition))
  end

end
