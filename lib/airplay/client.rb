class Airplay::Client
  attr_reader :servers, :active_server, :password

  def initialize(server = false, server_browser = Airplay::Server::Browser)
    @server_browser = server_browser
    browse unless server
    use servers.first if !@servers.nil?
  end

  def use(server)
    @active_server = server.is_a?(Airplay::Server::Node) ? server : @server_browser.find_by_name(server)
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
    Airplay::Protocol.new(@active_server.ip, @active_server.port, @password)
  end

  def send_image(image, transition = :none)
    Airplay::Protocol::Image.new(handler).send(image, transition)
  end

  def send_video(video, position = 0)
    Airplay::Protocol::Media.new(handler).send(video, position)
  end

  def send_audio(audio, position = 0)
    Airplay::Protocol::Media.new(handler).send(audio, position)
  end

  def scrub
    Airplay::Protocol::Scrub.new(handler).send
  end

end

class Airplay::Client::ServerNotFoundError < StandardError; end;
