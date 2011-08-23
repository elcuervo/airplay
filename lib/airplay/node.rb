class Airplay::Node
  attr_reader :name, :domain, :ip, :port

  def initialize(name, domain, ip, port)
    @name, @domain, @ip, @port = name, domain, ip, port
  end
end
