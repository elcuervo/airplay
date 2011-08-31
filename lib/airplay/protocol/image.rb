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
    content = case image
              when String
                if File.exists?(image)
                  File.read(image)
                else
                  image
                end
              when File
                image.read
              end

    put(resource, content, transition_header(transition))
  end

end
