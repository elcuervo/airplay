class Airplay::Client
  attr_reader :servers, :active_server

  def initialize(server = false)
    browse unless server
    use servers.first if servers.size == 1
  end

  def use(server)
    @active_server = server.is_a?(Airplay::Node) ? server : find_by_name(server)
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
      target = nil
      resolver.resolve(reply) do |resolved|
        target = resolved.target
        break unless resolved.flags.more_coming?
      end
      info = Socket.getaddrinfo(target, nil, Socket::AF_INET)
      ip_address = info[0][2]
      @servers << Airplay::Node.new(reply.name, reply.domain, ip_address)
      break unless reply.flags.more_coming?
    end
    @servers
  end

  def send_image(image, transition = :none)
    Airplay::Protocol::Image.new(@active_server.ip).send(image, transition)
  end

end

class Airplay::Client::ServerNotFoundError < StandardError; end;
