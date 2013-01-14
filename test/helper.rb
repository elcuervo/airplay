$:.unshift(File.expand_path("../lib", File.dirname(__FILE__)))

require "airplay"
require 'vcr'
require "cutest"

module MockedBrowser
  attr_reader :servers

  def self.browse
    @servers = [Airplay::Server::Node.new("Mock TV", ".local", "mocktv.local", 7000, nil)]
  end

  def self.find_by_name(name)
    if name == "Mock TV"
      @servers.first
    else
      raise Airplay::Client::ServerNotFoundError
    end
  end
end

VCR.configure do |c|
  c.cassette_library_dir = 'test/fixtures/cassettes/airplay'
  c.default_cassette_options = { :record => :once }
  c.hook_into :fakeweb
end

def with_cassette(name, &block)
  VCR.use_cassette(name, :preserve_exact_body_bytes => true) { block.call if block }
end
