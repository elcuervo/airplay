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
    {"X-Apple-Transition" => transitions.fetch(transition, :none)}
  end

  def send(image, transition = :none)
    image = URI.parse(image) if !(image =~ URI::regexp).nil?
    content = case image
              when String
                if File.exists?(image)
                  File.read(image)
                else
                  image
                end
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
