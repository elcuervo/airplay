class Airplay::Server::Node
  attr_reader :name, :domain, :ip, :port
  attr_reader :features, :deviceid, :model, :srcvers

  def initialize(name, domain, ip, port, info)
    @name, @domain, @ip, @port = name, domain, ip, port
    @features = Airplay::Server::Features.new info.fetch('features', 0).hex
    @deviceid = info.fetch('deviceid')
    @srcvers  = info.fetch('srcvers')
    @model    = info.fetch('model')
  end
end
