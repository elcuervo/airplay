class Airplay::ServerNotFoundError < StandardError; end;

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
    raise Airplay::ServerNotFoundError unless found_server
    found_server
  end

  def browse
    @servers = []
    DNSSD.browse!(Airplay::PROTOCOL_SEARCH) do |reply|
      @servers << Airplay::Node.new(reply.name, reply.domain, Addrinfo.ip(reply.name).ip_address)
      break if !reply.flags.more_coming?
    end
    @servers
  end

end
