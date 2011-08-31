$:.unshift(File.expand_path("../lib", File.dirname(__FILE__)))

require "airplay"
require 'vcr'
require 'mocha'
require "cutest"

VCR.config do |c|
  c.cassette_library_dir = 'test/fixtures/cassettes/airplay'
  c.default_cassette_options = { :record => :once }
  c.stub_with :fakeweb
end
