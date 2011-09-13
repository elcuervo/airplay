module Airplay::Server::Browser
  attr_reader :servers

  def self.find_by_name(name)
    found_server = @servers.detect do |server|
      server if server.name == name
    end
    raise Airplay::Client::ServerNotFoundError unless found_server
    found_server
  end

  def self.browse
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
      @servers << Airplay::Server::Node.new(reply.name, reply.domain, ip_address, port)
      break unless reply.flags.more_coming?
    end
    @servers
  end

end
