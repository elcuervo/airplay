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
    timeout 3 do
      DNSSD.browse!(Airplay::Protocol::SEARCH) do |node|
        resolver = DNSSD::Service.new
        target, port = nil
        resolver.resolve(node) do |resolved|
          port = resolved.port
          target = resolved.target
          break unless resolved.flags.more_coming?
        end
        info = Socket.getaddrinfo(target, nil, Socket::AF_INET)
        ip = info[0][2]
        @servers << Airplay::Server::Node.new(node.name, node.domain, ip, port)
        break unless node.flags.more_coming?
      end
    end
  rescue Timeout::Error
    raise Airplay::Client::ServerNotFoundError
  else
    @servers
  end

end
