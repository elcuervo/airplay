class Airplay::Protocol::Image

  def initialize(protocol_handler)
    @http = protocol_handler
  end

  def resource
    "/photo"
  end

  def transitions
    {
      :none         => "None",
      :slide_left   => "SlideLeft",
      :slide_right  => "SlideRight",
      :dissolve     => "Dissolve"
    }
  end

  def transition_header(transition)
    # The fallback value should be whatever transitions[:none] is above
    {"X-Apple-Transition" => transitions.fetch(transition, "None")}
  end

  def send(image, transition = :none)
    image = URI.parse(image) if !!(image =~ URI::regexp)
    content = case image
              when String
                File.exists?(image) ? File.read(image) : image
              when URI::HTTP then Net::HTTP.get(image)
              else
                if image.respond_to?(:read)
                  image.read
                else
                  throw Airplay::Protocol::InvalidMediaError
                end
              end

    @http.put(resource, content, transition_header(transition))
  end

end
