$:.unshift File.dirname(__FILE__) + '/../lib'

require "bundler/setup"
require "minitest/spec"
require "minitest/pride"
require "minitest/autorun"
require "vcr"
require "airplay"

VCR.configure do |c|
  c.cassette_library_dir = 'test/fixtures/cassettes/airplay'
  c.default_cassette_options = { record: :once }
  c.hook_into :fakeweb
end

def with_cassette(name, &block)
  VCR.use_cassette(name, preserve_exact_body_bytes: true, &block)
end
