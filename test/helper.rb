$:.unshift(File.expand_path("../lib", File.dirname(__FILE__)))

require "airplay"
require 'vcr'
require "cutest"

module MockedBrowser
  attr_reader :servers

  def self.browse
    @servers = [Airplay::Server::Node.new("Mock TV", ".local", "10.1.0.220", 7000)]
  end

  def self.find_by_name(name)
    if name == "Mock TV"
      @servers.first
    else
      raise Airplay::Client::ServerNotFoundError
    end
  end

end

VCR.config do |c|
  c.cassette_library_dir = 'test/fixtures/cassettes/airplay'
  c.default_cassette_options = { :record => :once }
  c.stub_with :fakeweb
end
