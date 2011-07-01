class Airplay::Node
  attr_reader :name, :domain, :ip

  def initialize(name, domain, ip)
    @name, @domain, @ip = name, domain, ip
  end
end
