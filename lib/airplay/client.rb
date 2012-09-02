class Airplay::Client
  attr_reader :servers, :active, :password

  def initialize(server = false, server_browser = Airplay::Server::Browser)
    @server_browser = server_browser
    browse unless server
    use servers.first if !@servers.nil?
  end

  def use(server)
    @active = if server.is_a?(Airplay::Server::Node)
                       server
                     else
                       @server_browser.find_by_name(server)
                     end
  end

  def password(password)
    @password = password
  end

  def find_by_name(name)
    @server_browser.find_by_name(name)
  end

  def browse
    @servers = @server_browser.browse
  end

  def handler
    @_handler ||= Airplay::Protocol.new(@active.ip, @active.port, @password)
  end

  def send_image(image, transition = :none, *args)
    @image_proxy ||= Airplay::Protocol::Image.new(handler)
    @image_proxy.send(image, transition, *args)
  end

  def send_video(video, position = 0)
    @media_proxy ||= Airplay::Protocol::Media.new(handler)
    @media_proxy.send(video, position)
  end

  def send_audio(audio, position = 0)
    @media_proxy ||= Airplay::Protocol::Media.new(handler)
    @media_proxy.send(audio, position)
  end

  def scrub(position = false)
    @scrub_proxy ||= Airplay::Protocol::Scrub.new(handler)
    if position
      @scrub_proxy.to position
    else
      @scrub_proxy.check
    end
  end

end

class Airplay::Client::ServerNotFoundError < StandardError; end;
