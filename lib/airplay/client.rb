class Airplay::Client
  attr_reader :servers, :active_server, :password

  def initialize(server = false)
    browse unless server
    use servers.first if servers.any?
  end

  def use(server)
    @active_server = server.is_a?(Airplay::Node) ? server : find_by_name(server)
  end

  def password(password)
    @password = password
  end

  def find_by_name(name)
    found_server =  @servers.detect do |server|
      server if server.name == name
    end
    raise Airplay::Client::ServerNotFoundError unless found_server
    found_server
  end

  def browse
    @servers = []
    DNSSD.browse!(Airplay::Protocol::SEARCH) do |reply|
      resolver = DNSSD::Service.new
      target, port = nil
      resolver.resolve(reply) do |resolved|
        port = resolved.port
        target = resolved.target
        break unless resolved.flags.more_coming?
      end
      info = Socket.getaddrinfo(target, nil, Socket::AF_INET)
      ip_address = info[0][2]
      @servers << Airplay::Node.new(reply.name, reply.domain, ip_address, port)
      break unless reply.flags.more_coming?
    end
    @servers
  end

  def handler
    Airplay::Protocol.new(@active_server.ip, @active_server.port, @password)
  end

  def send_image(image, transition = :none)
    Airplay::Protocol::Image.new(handler).send(image, transition)
  end

  def send_video(video, position = 0)
    Airplay::Protocol::Video.new(handler).send(video, position)
  end

  def scrub
    Airplay::Protocol::Scrub.new(handler).send
  end

end

class Airplay::Client::ServerNotFoundError < StandardError; end;
